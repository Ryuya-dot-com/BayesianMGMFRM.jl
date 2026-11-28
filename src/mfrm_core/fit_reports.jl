# fit_reports.jl -- Structured fit reports, JSON canonicalization, public reader projection, and table exports.

const _FIT_REPORT_WARMUP_INTERPRETATION = "Warmup describes NUTS adaptation or random-walk burn-in. Random walk reports rejected nonfinite proposals; its NUTS event fields do not apply. These counts remain separate from convergence diagnostics and retained-draw warnings. Coverage: recorded = observed; not_run = known zero warmup; not_recorded = history unavailable. Unavailable or inapplicable counts are null in JSON and blank in Markdown, never zero. No warmup pass/fail rule is applied."

function _fit_report_on_section_error(on_section_error::Symbol)
    on_section_error in (:capture, :throw) ||
        throw(ArgumentError("on_section_error must be :capture or :throw"))
    return on_section_error
end

function _fit_report_section(thunk, on_section_error::Symbol)
    try
        return merge((; status = :computed), thunk())
    catch err
        _fatal_exception(err) && rethrow()
        on_section_error === :throw && rethrow()
        return (;
            status = :error,
            exception = Symbol(nameof(typeof(err))),
            message = sprint(showerror, err),
        )
    end
end

_fit_report_not_requested() = (; status = :not_requested)

function _fit_report_unsupported(reason::AbstractString)
    return (;
        status = :unsupported,
        reason = String(reason),
    )
end

function _fit_report_fixed_coordinate_row(row)
    block = getproperty(row, :block)
    level = getproperty(row, :level)
    return (;
        parameter = string(block, "[", level, "]"),
        facet = block,
        level_index = getproperty(row, :level_index),
        level,
        fixed_value = getproperty(row, :value),
        constraint = getproperty(row, :status),
        source = getproperty(row, :source),
        sampled = false,
        prior_applied = false,
        posterior_estimated = false,
        uncertainty_status = :not_applicable_fixed_by_identification,
    )
end

function _fit_report_fixed_coordinates(fit::MFRMFit, manifest,
        on_section_error::Symbol)
    return _fit_report_section(on_section_error) do
        design_manifest = manifest.design
        hasproperty(design_manifest, :fixed_coordinates) ||
            throw(ArgumentError(
                "MFRM design manifest does not expose fixed coordinates"))
        source_rows = design_manifest.fixed_coordinates
        rows = [_fit_report_fixed_coordinate_row(row) for row in source_rows]
        hard_anchor_rows = [row for row in rows
            if row.constraint === :hard_anchor]
        reference_rows = [row for row in rows
            if row.constraint === :reference_zero]
        n_hard_anchors = length(hard_anchor_rows)
        hard_anchor_counts = (;
            rater = count(row -> row.facet === :rater, hard_anchor_rows),
            item = count(row -> row.facet === :item, hard_anchor_rows),
        )
        multi_anchor_facets = Tuple(facet for facet in (:rater, :item)
            if getproperty(hard_anchor_counts, facet) >= 2)
        n_multi_anchor_coordinates = sum(
            getproperty(hard_anchor_counts, facet)
            for facet in multi_anchor_facets;
            init = 0,
        )
        warning_rows = n_hard_anchors == 0 ? NamedTuple[] : [
            (;
                code = :hard_anchor_fixed_not_estimated,
                severity = :warning,
                n_coordinates = n_hard_anchors,
                n_affected_rows = n_hard_anchors,
                action = :interpret_fixed_coordinate_rows_as_constants,
                message = string(
                    n_hard_anchors,
                    n_hard_anchors == 1 ?
                        " hard-anchored facet coordinate is" :
                        " hard-anchored facet coordinates are",
                    " fixed by design; ",
                    n_hard_anchors == 1 ? "it is" : "they are",
                    " excluded from posterior summaries and receive no prior or sampling uncertainty. ",
                    "Uncertainty in externally estimated anchor values is not propagated.",
                ),
            ),
            (;
                code = :hard_anchor_zero_centered_prior_coordinate_dependence,
                severity = :warning,
                n_coordinates = n_hard_anchors,
                n_affected_rows = n_hard_anchors,
                action = :treat_anchor_and_free_coordinate_prior_as_joint_model_assumption,
                message = string(
                    "MFRMPrior remains zero-centered on the free identified ",
                    "coordinates and is not shifted with hard-anchor values; ",
                    "changing an anchor can therefore change prior and posterior ",
                    "predictions even when a likelihood-equivalent reparameterization exists.",
                ),
            ),
        ]
        prior_reference_rows = [row for row in reference_rows
            if !isempty(fit.design.blocks[row.facet])]
        if !isempty(prior_reference_rows)
            push!(warning_rows, (;
                code = :reference_zero_prior_coordinate_dependence,
                severity = :warning,
                n_coordinates = length(prior_reference_rows),
                n_affected_rows = length(prior_reference_rows),
                action = :preserve_reference_or_transport_joint_prior,
                message = string(
                    "Default zero references: ",
                    join((row.parameter for row in prior_reference_rows), ", "),
                    ". MFRMPrior assigns independent zero-centered priors to free coordinates. ",
                    "Changing the reference through relabeling without transporting the joint prior ",
                    "can change posterior predictions and decisions. Stored label order, not input ",
                    "row order, selects these references; they are coding conventions, not external calibrations.",
                ),
            ))
        end
        if !isempty(multi_anchor_facets)
            push!(warning_rows, (;
                code = :multiple_hard_anchors_fix_within_facet_contrasts,
                severity = :warning,
                n_coordinates = n_multi_anchor_coordinates,
                n_affected_rows = n_multi_anchor_coordinates,
                action = :validate_anchor_contrasts_and_run_contamination_sensitivity,
                message = string(
                    "Multiple hard anchors occur within the ",
                    join(string.(multi_anchor_facets), " and "),
                    length(multi_anchor_facets) == 1 ? " facet; " : " facets; ",
                    "they fix within-facet contrasts rather than only location gauges. ",
                    "Validate source invariance and run predeclared contamination or drift sensitivity.",
                ),
            ))
        end
        (;
            schema = "bayesianmgmfrm.fit_report_fixed_coordinates.v1",
            rows,
            n_rows = length(rows),
            warning_rows,
            n_warning_rows = length(warning_rows),
            summary = (;
                n_fixed_coordinates = length(rows),
                n_hard_anchors,
                hard_anchor_counts,
                n_default_reference_coordinates = length(reference_rows),
                n_sampled_coordinates = 0,
                n_posterior_estimated_coordinates = 0,
                hard_anchor_warning = n_hard_anchors > 0,
                hard_anchor_value_uncertainty_status = n_hard_anchors > 0 ?
                    :not_propagated_exact_fixed_values : :not_applicable,
                hard_anchor_prior_coordinate_dependence =
                    n_hard_anchors > 0,
                within_facet_anchor_contrast_restriction =
                    !isempty(multi_anchor_facets),
                fixed_coordinates_in_posterior_rows = false,
                interpretation =
                    :fixed_identification_constants_not_posterior_estimates,
            ),
        )
    end
end

function _fit_report_fixed_coordinates(fit::Union{GMFRMFit,MGMFRMFit},
        manifest, on_section_error::Symbol)
    return _fit_report_unsupported(
        "individual item/rater fixed-coordinate reporting is available for stable MFRM fits; generalized gauge coordinates remain in their dedicated report sections",
    )
end

function _fit_report_category_functioning(fit::MFRMFit;
        include_category_functioning::Bool,
        interval::Real,
        min_count::Int,
        min_proportion::Real,
        order_probability_threshold::Real,
        draw_indices,
        rng::AbstractRNG,
        on_section_error::Symbol)
    include_category_functioning || return _fit_report_not_requested()
    return _fit_report_section(on_section_error) do
        result = category_functioning_summary(fit;
            interval,
            min_count,
            min_proportion,
            order_probability_threshold,
            draw_indices,
            rng,
        )
        n_review_rows = result.summary.n_review_rows
        warning_rows = n_review_rows == 0 ? NamedTuple[] : [(;
            code = :category_functioning_review_recommended,
            severity = :warning,
            n_affected_rows = n_review_rows,
            action = :review_category_usage_and_step_rows_before_recode_or_refit,
            message = string(
                n_review_rows,
                n_review_rows == 1 ?
                    " category-functioning row requires" :
                    " category-functioning rows require",
                " review; the report does not automatically collapse, recode, or refit categories.",
            ),
        )]
        return merge(result, (;
            usage_rows = collect(result.usage_rows),
            threshold_rows = collect(result.threshold_rows),
            warning_rows,
            n_warning_rows = length(warning_rows),
        ))
    end
end

function _fit_report_category_functioning(fit::Union{GMFRMFit,MGMFRMFit};
        include_category_functioning::Bool,
        kwargs...)
    include_category_functioning || return _fit_report_not_requested()
    return _fit_report_unsupported(
        "category-functioning report rows are currently available for stable MFRM/RSM/PCM fits only",
    )
end

function _fit_report_rater_homogeneity(fit::MFRMFit;
        include_rater_homogeneity::Bool,
        interval::Real,
        severity_rope,
        rope_probability_threshold::Real,
        overlap_unit::Symbol,
        min_shared_units::Int,
        draw_indices,
        rng::AbstractRNG,
        on_section_error::Symbol)
    include_rater_homogeneity || return _fit_report_not_requested()
    return _fit_report_section(on_section_error) do
        result = rater_homogeneity_summary(fit;
            interval,
            severity_rope,
            rope_probability_threshold,
            overlap_unit,
            min_shared_units,
            draw_indices,
            rng,
        )
        n_unsupported =
            result.summary.n_model_identification_unsupported_contrasts
        warning_rows = n_unsupported == 0 ? NamedTuple[] : [(;
            code = :rater_homogeneity_identification_unsupported,
            severity = :warning,
            n_affected_rows = n_unsupported,
            action = :do_not_interpret_unsupported_rater_contrasts,
            message = string(
                n_unsupported,
                n_unsupported == 1 ?
                    " rater contrast lacks" :
                    " rater contrasts lack",
                " supported additive-model identification and must not be interpreted.",
            ),
        )]
        return merge(result, (;
            contrast_rows = collect(result.contrast_rows),
            warning_rows,
            n_warning_rows = length(warning_rows),
        ))
    end
end

function _fit_report_rater_homogeneity(fit::Union{GMFRMFit,MGMFRMFit};
        include_rater_homogeneity::Bool,
        kwargs...)
    include_rater_homogeneity || return _fit_report_not_requested()
    return _fit_report_unsupported(
        "rater-homogeneity report rows are currently available for stable MFRM/RSM/PCM fits only",
    )
end

function _fit_report_prior_predictive(fit::MFRMFit;
        include_prior_predictive::Bool,
        prior_predictive_ndraws::Int,
        prior_predictive_rng::AbstractRNG,
        predictive_interval::Real,
        include_grouped_predictive::Bool,
        on_section_error::Symbol)
    include_prior_predictive || return _fit_report_not_requested()
    return _fit_report_section(on_section_error) do
        check = prior_predictive_check(fit.design;
            prior = fit.prior,
            ndraws = prior_predictive_ndraws,
            rng = prior_predictive_rng)
        rows = predictive_check_summary(check;
            interval = predictive_interval,
            include_grouped = include_grouped_predictive)
        (;
            ndraws = prior_predictive_ndraws,
            rows,
            n_rows = length(rows),
            implication_diagnostics = check.implication_diagnostics,
        )
    end
end

function _fit_report_prior_predictive(fit::_ModelComparisonFit;
        include_prior_predictive::Bool,
        kwargs...)
    include_prior_predictive || return _fit_report_not_requested()
    return _fit_report_unsupported(
        "prior predictive reporting is currently implemented for MFRMFit only",
    )
end

function _fit_report_direct_posterior(fit::MFRMFit; include_direct_posterior::Bool,
        kwargs...)
    include_direct_posterior || return _fit_report_not_requested()
    return _fit_report_unsupported(
        "direct constrained posterior rows are only available for guarded generalized fits",
    )
end

function _fit_report_direct_posterior(fit::Union{GMFRMFit,MGMFRMFit};
        include_direct_posterior::Bool,
        posterior_lower::Real,
        posterior_upper::Real,
        posterior_intervals,
        posterior_reference::Real,
        posterior_rope,
        posterior_rope_probability_threshold::Real,
        on_section_error::Symbol)
    include_direct_posterior || return _fit_report_not_requested()
    return _fit_report_section(on_section_error) do
        rows = direct_posterior_summary(fit;
            lower = posterior_lower,
            upper = posterior_upper,
            intervals = posterior_intervals,
            reference = posterior_reference,
            rope = posterior_rope,
            rope_probability_threshold = posterior_rope_probability_threshold)
        (;
            rows,
            n_rows = length(rows),
            interpretation = "Model coordinates after positive and identification transforms. The response multiplier is $(fit isa GMFRMFit ? 1.0 : 1.7); it is not absorbed into item discrimination or rater consistency. Use the optional effective_slopes section for their joint-draw adjacent-logit slopes.",
        )
    end
end

function _fit_report_dff(fit::MFRMFit;
        include_dff::Bool,
        dff_terms,
        dff_interval::Real,
        dff_min_n::Int,
        dff_adjustment::Symbol,
        dff_expected_score_practical_threshold,
        dff_logit_practical_threshold,
        dff_practical_probability_threshold::Real,
        ndraws,
        draw_indices,
        rng::AbstractRNG,
        on_section_error::Symbol)
    include_dff || return _fit_report_not_requested()
    return _fit_report_section(on_section_error) do
        rows = dff_report(fit;
            terms = dff_terms,
            interval = dff_interval,
            min_n = dff_min_n,
            adjustment = dff_adjustment,
            expected_score_practical_threshold =
                dff_expected_score_practical_threshold,
            logit_practical_threshold = dff_logit_practical_threshold,
            practical_probability_threshold = dff_practical_probability_threshold,
            ndraws,
            draw_indices,
            rng)
        (;
            rows,
            n_rows = length(rows),
        )
    end
end

function _fit_report_dff(fit::_ModelComparisonFit; include_dff::Bool, kwargs...)
    include_dff || return _fit_report_not_requested()
    return _fit_report_unsupported(
        "DFF screening report rows are currently implemented for MFRMFit only",
    )
end

function _fit_report_prior_policy_row(; family::Symbol, block::Symbol,
        parameter_space::Symbol, prior_family::Symbol, location::Real,
        scale_parameter::Symbol, scale::Real, active::Bool,
        direct_scale_prior::Bool, jacobian_policy::Symbol, status::Symbol,
        note::AbstractString)
    return (;
        schema = "bayesianmgmfrm.fit_report_prior_policy_row.v1",
        family,
        block,
        parameter_space,
        prior_family,
        location = Float64(location),
        scale_parameter,
        scale = Float64(scale),
        independent_by_parameter = true,
        active,
        direct_scale_prior,
        jacobian_policy,
        status,
        note,
    )
end

function _fit_report_prior_policy_rows(fit::MFRMFit)
    prior = fit.prior
    return [
        _fit_report_prior_policy_row(
            family = :mfrm,
            block = :person,
            parameter_space = :identified_constrained_parameter,
            prior_family = :normal,
            location = 0.0,
            scale_parameter = :person_sd,
            scale = prior.person_sd,
            active = true,
            direct_scale_prior = true,
            jacobian_policy = :identity,
            status = :active,
            note = "weakly informative independent normal prior on identified person measures",
        ),
        _fit_report_prior_policy_row(
            family = :mfrm,
            block = :rater,
            parameter_space = :identified_constrained_parameter,
            prior_family = :normal,
            location = 0.0,
            scale_parameter = :rater_sd,
            scale = prior.rater_sd,
            active = true,
            direct_scale_prior = true,
            jacobian_policy = :identity,
            status = :active,
            note = "weakly informative independent normal prior on identified rater severities",
        ),
        _fit_report_prior_policy_row(
            family = :mfrm,
            block = :item,
            parameter_space = :identified_constrained_parameter,
            prior_family = :normal,
            location = 0.0,
            scale_parameter = :item_sd,
            scale = prior.item_sd,
            active = true,
            direct_scale_prior = true,
            jacobian_policy = :identity,
            status = :active,
            note = "weakly informative independent normal prior on identified item difficulties",
        ),
        _fit_report_prior_policy_row(
            family = :mfrm,
            block = :thresholds,
            parameter_space = :identified_constrained_parameter,
            prior_family = :normal,
            location = 0.0,
            scale_parameter = :step_sd,
            scale = prior.step_sd,
            active = true,
            direct_scale_prior = true,
            jacobian_policy = :identity,
            status = :active,
            note = "weakly informative independent normal prior on identified threshold or step parameters",
        ),
    ]
end

function _fit_report_prior_policy_rows(fit::Union{GMFRMFit,MGMFRMFit})
    prior = fit.prior
    family = fit.design.spec.family
    loading_block = family === :mgmfrm ?
        :log_item_dimension_discrimination :
        :log_item_discrimination
    return [
        _fit_report_prior_policy_row(
            family = family,
            block = :person,
            parameter_space = :raw_unconstrained_coordinate,
            prior_family = :normal,
            location = 0.0,
            scale_parameter = :person_sd,
            scale = prior.person_sd,
            active = true,
            direct_scale_prior = false,
            jacobian_policy = :none_raw_coordinate_density,
            status = :active,
            note = "guarded generalized fit uses an independent normal raw-coordinate prior for person locations",
        ),
        _fit_report_prior_policy_row(
            family = family,
            block = :rater,
            parameter_space = :raw_unconstrained_coordinate,
            prior_family = :normal,
            location = 0.0,
            scale_parameter = :rater_sd,
            scale = prior.rater_sd,
            active = true,
            direct_scale_prior = false,
            jacobian_policy = :none_raw_coordinate_density,
            status = :active,
            note = "guarded generalized fit uses an independent normal raw-coordinate prior for rater severities",
        ),
        _fit_report_prior_policy_row(
            family = family,
            block = :item,
            parameter_space = :raw_unconstrained_coordinate,
            prior_family = :normal,
            location = 0.0,
            scale_parameter = :item_sd,
            scale = prior.item_sd,
            active = true,
            direct_scale_prior = false,
            jacobian_policy = :none_raw_coordinate_density,
            status = :active,
            note = "guarded generalized fit uses an independent normal raw-coordinate prior for item difficulties",
        ),
        _fit_report_prior_policy_row(
            family = family,
            block = loading_block,
            parameter_space = :raw_log_positive_coordinate,
            prior_family = :normal,
            location = 0.0,
            scale_parameter = :log_discrimination_sd,
            scale = prior.log_discrimination_sd,
            active = true,
            direct_scale_prior = false,
            jacobian_policy = :none_raw_coordinate_density,
            status = :active,
            note = "positive discrimination or loading parameters are represented by raw log coordinates",
        ),
        _fit_report_prior_policy_row(
            family = family,
            block = :log_rater_consistency,
            parameter_space = :raw_log_positive_coordinate,
            prior_family = :normal,
            location = 0.0,
            scale_parameter = :log_consistency_sd,
            scale = prior.log_consistency_sd,
            active = true,
            direct_scale_prior = false,
            jacobian_policy = :none_raw_coordinate_density,
            status = :active,
            note = "positive rater consistency parameters are represented by raw log coordinates",
        ),
        _fit_report_prior_policy_row(
            family = family,
            block = :steps,
            parameter_space = :raw_constrained_step_coordinate,
            prior_family = :normal,
            location = 0.0,
            scale_parameter = :step_sd,
            scale = prior.step_sd,
            active = true,
            direct_scale_prior = false,
            jacobian_policy = :none_raw_coordinate_density,
            status = :active,
            note = "category step parameters use the guarded generalized raw-coordinate prior scale",
        ),
        _fit_report_prior_policy_row(
            family = family,
            block = :direct_scale_generalized_priors,
            parameter_space = :direct_constrained_parameter,
            prior_family = :not_enabled,
            location = 0.0,
            scale_parameter = :not_applicable,
            scale = 0.0,
            active = false,
            direct_scale_prior = true,
            jacobian_policy = :requires_future_log_jacobian_policy,
            status = :blocked,
            note = "direct-scale generalized priors remain disabled until a log-Jacobian policy is implemented",
        ),
    ]
end

function _fit_report_raw_prior_control_manifest(fit::MFRMFit)
    return nothing
end

function _fit_report_raw_prior_control_manifest(fit::GMFRMFit)
    base_manifest = model_manifest(fit.design)
    promotion = base_manifest.design.raw_parameterization.promotion_candidate
    return _resolved_generalized_raw_prior_control_manifest(
        promotion.experimental_public_api.raw_prior_control_manifest,
        fit.prior,
    )
end

function _fit_report_raw_prior_control_manifest(fit::MGMFRMFit)
    base_manifest = model_manifest(fit.design)
    confirmatory = base_manifest.design.raw_parameterization.confirmatory_candidate
    return _resolved_generalized_raw_prior_control_manifest(
        confirmatory.experimental_public_api_decision.raw_prior_control_manifest,
        fit.prior,
    )
end

function _fit_report_prior_policy(fit::_ModelComparisonFit)
    rows = _fit_report_prior_policy_rows(fit)
    raw_prior_control_manifest = _fit_report_raw_prior_control_manifest(fit)
    return (;
        status = :computed,
        schema = "bayesianmgmfrm.fit_report_prior_policy.v1",
        rows,
        n_rows = length(rows),
        raw_prior_control_manifest,
        summary = (;
            n_active_rows = count(row -> row.active, rows),
            n_blocked_rows = count(row -> row.status === :blocked, rows),
            all_active_priors_independent = all(row -> row.independent_by_parameter,
                filter(row -> row.active, rows)),
            direct_scale_generalized_priors_enabled =
                any(row -> row.active && row.direct_scale_prior &&
                    row.family in (:gmfrm, :mgmfrm),
                    rows),
            raw_coordinate_generalized_priors =
                fit isa Union{GMFRMFit,MGMFRMFit},
            raw_prior_control_manifest_recorded =
                raw_prior_control_manifest !== nothing,
            raw_prior_control_all_active_scales_resolved =
                raw_prior_control_manifest === nothing ? missing :
                raw_prior_control_manifest.summary.all_active_scales_resolved,
            jacobian_policy = fit isa MFRMFit ?
                :identity :
                :none_raw_coordinate_density,
        ),
    )
end

function _fit_report_pooling_policy_row(; family::Symbol, block::Symbol,
        pooling::Symbol, active::Bool, status::Symbol, blocker::Symbol,
        note::AbstractString)
    return (;
        schema = "bayesianmgmfrm.fit_report_pooling_policy_row.v1",
        family,
        block,
        pooling,
        active,
        status,
        blocker,
        note,
    )
end

function _fit_report_pooling_policy(fit::_ModelComparisonFit)
    family = fit.design.spec.family
    rows = [
        _fit_report_pooling_policy_row(
            family = family,
            block = :facet_parameters,
            pooling = :independent_priors,
            active = true,
            status = :active,
            blocker = :not_applicable,
            note = "v0.1.x fits use independent priors for exposed facet parameter blocks",
        ),
        _fit_report_pooling_policy_row(
            family = family,
            block = :facet_hyperparameters,
            pooling = :hierarchical_partial_pooling,
            active = false,
            status = :blocked,
            blocker = :hierarchical_estimands_hyperpriors_shrinkage_diagnostics_sensitivity_missing,
            note = "hierarchical facet priors require explicit estimands, hyperpriors, shrinkage diagnostics, and sensitivity evidence",
        ),
        _fit_report_pooling_policy_row(
            family = family,
            block = :rater_consistency,
            pooling = :hierarchical_rater_consistency_pooling,
            active = false,
            status = family === :mfrm ? :not_applicable : :blocked,
            blocker = family === :mfrm ? :not_a_generalized_fit :
                :generalized_pooling_policy_not_promoted,
            note = family === :mfrm ?
                "minimal MFRM has no rater-consistency parameter" :
                "guarded generalized fits do not partially pool rater consistency in v0.1.x",
        ),
    ]
    return (;
        status = :computed,
        schema = "bayesianmgmfrm.fit_report_pooling_policy.v1",
        rows,
        n_rows = length(rows),
        summary = (;
            independent_priors_default = true,
            hierarchical_pooling_active = any(row -> row.active &&
                row.pooling !== :independent_priors,
                rows),
            n_blocked_rows = count(row -> row.status === :blocked, rows),
            partial_pooling_claims_allowed = false,
            next_gate = :hierarchical_estimands_hyperpriors_shrinkage_diagnostics_sensitivity,
        ),
    )
end

const _MGMFRM_LOCAL_GUIDANCE_PRESET = :brms_like
const _MGMFRM_LOCAL_GUIDANCE_MIN_CHAINS = 4
const _MGMFRM_LOCAL_GUIDANCE_MIN_WARMUP_PER_CHAIN = 1000
const _MGMFRM_LOCAL_GUIDANCE_MIN_DRAWS_PER_CHAIN = 1000
const _MGMFRM_LOCAL_GUIDANCE_REFERENCE_DRAWS_PER_CHAIN = 1000
const _MGMFRM_LOCAL_GUIDANCE_TOTAL_ITER_PER_CHAIN =
    _MGMFRM_LOCAL_GUIDANCE_MIN_WARMUP_PER_CHAIN +
    _MGMFRM_LOCAL_GUIDANCE_MIN_DRAWS_PER_CHAIN

function _fit_report_mcmc_budget_guidance_row(; family::Symbol,
        recommendation::Symbol, status::Symbol, applies::Bool,
        current_value, recommended_minimum, evidence::Symbol,
        action::Symbol, note::AbstractString)
    return (;
        schema = "bayesianmgmfrm.fit_report_mcmc_budget_guidance_row.v1",
        family,
        recommendation,
        status,
        applies,
        current_value,
        recommended_minimum,
        evidence,
        action,
        public_claim_allowed = false,
        package_default_change = false,
        note,
    )
end

function _fit_report_mcmc_budget_guidance(fit::_ModelComparisonFit, metadata,
        diagnostic_surface)
    family = fit.design.spec.family
    family === :mgmfrm ||
        return _fit_report_unsupported(
            "local retained-draw budget guidance is currently documented for guarded MGMFRM fits only",
        )
    current_chains = Int(metadata.n_chains)
    current_warmup = Int(metadata.warmup)
    current_draws = Int(metadata.draws_per_chain)
    summary = diagnostic_surface.summary
    geometry_warning_rows =
        Int(_nt_get(summary, :n_divergences, 0)) +
        Int(_nt_get(summary, :n_max_treedepth, 0)) +
        Int(_nt_get(summary, :n_sampler_warnings, 0))
    meets_chains = current_chains >= _MGMFRM_LOCAL_GUIDANCE_MIN_CHAINS
    meets_warmup = current_warmup >= _MGMFRM_LOCAL_GUIDANCE_MIN_WARMUP_PER_CHAIN
    meets_draws = current_draws >= _MGMFRM_LOCAL_GUIDANCE_MIN_DRAWS_PER_CHAIN
    rows = [
        _fit_report_mcmc_budget_guidance_row(
            family = family,
            recommendation = :local_mgmfrm_diagnostic_budget,
            status = meets_chains && meets_warmup && meets_draws ?
                :met : :not_met,
            applies = true,
            current_value = (;
                chains = current_chains,
                warmup_per_chain = current_warmup,
                draws_per_chain = current_draws,
            ),
            recommended_minimum = (;
                preset = _MGMFRM_LOCAL_GUIDANCE_PRESET,
                chains = _MGMFRM_LOCAL_GUIDANCE_MIN_CHAINS,
                warmup_per_chain = _MGMFRM_LOCAL_GUIDANCE_MIN_WARMUP_PER_CHAIN,
                draws_per_chain = _MGMFRM_LOCAL_GUIDANCE_MIN_DRAWS_PER_CHAIN,
                total_iterations_per_chain =
                    _MGMFRM_LOCAL_GUIDANCE_TOTAL_ITER_PER_CHAIN,
            ),
            evidence = :brms_like_default_and_local_1000_draw_rank_replication,
            action = meets_chains && meets_warmup && meets_draws ?
                :continue_standard_diagnostic_review :
                :increase_budget_before_substantive_rank_warning_interpretation,
            note = "report guidance recommends a brms-like guarded MGMFRM budget: 4 chains, 1000 warmup draws, and 1000 retained draws per chain before treating rank warnings as substantive evidence",
        ),
        _fit_report_mcmc_budget_guidance_row(
            family = family,
            recommendation = :rank_warning_escalation_order,
            status = current_draws >= _MGMFRM_LOCAL_GUIDANCE_REFERENCE_DRAWS_PER_CHAIN ?
                :active : :below_reference_budget,
            applies = true,
            current_value = current_draws,
            recommended_minimum = _MGMFRM_LOCAL_GUIDANCE_MIN_DRAWS_PER_CHAIN,
            evidence = :local_1000_draw_rank_replication_review,
            action = geometry_warning_rows == 0 &&
                     current_draws < _MGMFRM_LOCAL_GUIDANCE_MIN_DRAWS_PER_CHAIN ?
                :increase_retained_draws_before_reparameterizing_or_thinning :
                :review_rank_and_geometry_diagnostics_together,
            note = "use 1000 retained draws as the report-facing guarded MGMFRM rank-guidance budget and review divergences or treedepth warnings through a separate geometry branch",
        ),
        _fit_report_mcmc_budget_guidance_row(
            family = family,
            recommendation = :warmup_policy,
            status = current_warmup >= _MGMFRM_LOCAL_GUIDANCE_MIN_WARMUP_PER_CHAIN ?
                :met : :below_brms_like_budget,
            applies = true,
            current_value = current_warmup,
            recommended_minimum = _MGMFRM_LOCAL_GUIDANCE_MIN_WARMUP_PER_CHAIN,
            evidence = :brms_iter_2000_warmup_half_convention,
            action = geometry_warning_rows > 0 &&
                     current_warmup < _MGMFRM_LOCAL_GUIDANCE_MIN_WARMUP_PER_CHAIN ?
                :increase_warmup_or_target_acceptance_for_geometry_warning :
                :use_brms_like_warmup_for_substantive_mgmfrm_diagnostics,
            note = "brms uses total iterations including warmup, with a default warmup of iter/2; the analogous package guidance is warmup = 1000 and retained draws = 1000 per chain",
        ),
        _fit_report_mcmc_budget_guidance_row(
            family = family,
            recommendation = :thinning_policy,
            status = :not_primary_fix,
            applies = true,
            current_value = :not_exposed_in_fit_api,
            recommended_minimum = :not_applicable,
            evidence = :thinning_reduces_diagnostic_support,
            action = :do_not_use_thinning_as_primary_fix,
            note = "post-hoc thinning can reduce diagnostic support and is not exposed as the primary guarded fit API control",
        ),
        _fit_report_mcmc_budget_guidance_row(
            family = family,
            recommendation = :package_default_policy,
            status = :blocked_for_default_change,
            applies = true,
            current_value = :current_fit_controls,
            recommended_minimum = :brms_like_report_guidance_not_global_fit_default,
            evidence = :public_defaults_require_runtime_and_external_construct_review,
            action = :do_not_change_package_defaults_from_this_local_gate,
            note = "this is report-facing guarded MGMFRM diagnostic guidance, not a package-wide fit default change or public fit-threshold claim",
        ),
    ]
    return (;
        status = :computed,
        schema = "bayesianmgmfrm.fit_report_mcmc_budget_guidance.v1",
        rows,
        n_rows = length(rows),
        summary = (;
            family,
            current_chains,
            current_warmup_per_chain = current_warmup,
            current_draws_per_chain = current_draws,
            recommended_preset = _MGMFRM_LOCAL_GUIDANCE_PRESET,
            recommended_min_chains = _MGMFRM_LOCAL_GUIDANCE_MIN_CHAINS,
            recommended_min_warmup_per_chain =
                _MGMFRM_LOCAL_GUIDANCE_MIN_WARMUP_PER_CHAIN,
            recommended_min_draws_per_chain =
                _MGMFRM_LOCAL_GUIDANCE_MIN_DRAWS_PER_CHAIN,
            recommended_total_iterations_per_chain =
                _MGMFRM_LOCAL_GUIDANCE_TOTAL_ITER_PER_CHAIN,
            recommended_total_retained_draws =
                _MGMFRM_LOCAL_GUIDANCE_MIN_CHAINS *
                _MGMFRM_LOCAL_GUIDANCE_MIN_DRAWS_PER_CHAIN,
            current_budget_meets_guidance =
                meets_chains && meets_warmup && meets_draws,
            geometry_warning_rows,
            thinning_primary_fix = false,
            package_default_change = false,
            public_fit_metric_claim_allowed = false,
            next_gate =
                :join_brms_like_budget_guidance_to_model_comparison_and_calibration,
        ),
    )
end

"""
    fit_report(fit; view = :full, kwargs...)

Build a compact, machine-readable report bundle for a fitted MFRM, guarded
GMFRM, or guarded MGMFRM object. The report combines fit metadata, provenance,
diagnostics, fixed-coordinate identification rows, prior, pooling, and MGMFRM
local MCMC-budget guidance rows, posterior summaries, posterior predictive
summaries, category-functioning and rater-homogeneity rows, calibration rows,
WAIC/LOO summaries and diagnostics, optional DFF rows, and a compact archive
manifest. Stable MFRM category/rater practitioner sections are included by
default and can be disabled independently. Stable MFRM fixed-coordinate rows state
explicitly that reference and hard-anchor values are constants rather than
posterior estimates; hard anchors also produce concise fixed-coordinate and
coordinate-dependent-prior warnings, plus a within-facet contrast warning when
two or more anchors occur in the same facet.
Section-level failures are captured by default with `status = :error` and make
the top-level `report_status = :incomplete`. Use
`on_section_error = :throw` to make the first failing section raise, or
`require_complete = true` to evaluate all captured sections and then reject an
incomplete report. `InterruptException`, `OutOfMemoryError` and
`StackOverflowError` always propagate, including under the default capture policy.

Set `include_prior_predictive = true` for MFRM fits to include prior predictive
summary rows. Use `include_full_artifact = true` to embed the full compact
`fit_artifact`; otherwise only the artifact schema, content hash, and archive
manifest are included in the report. The default `view = :full` preserves the
complete `bayesianmgmfrm.fit_report.v1` compatibility payload. Set
`view = :public` to return the reader-facing structured projection produced by
[`fit_report_public`](@ref).

The `warmup` section includes chain-level adaptation coverage and event counts
from `sampler_diagnostics(fit; phase = :warmup)`. It is included in structured,
public, Markdown, table and bundle outputs. Unrecorded history has missing
counts; known zero-warmup runs are labelled `:not_run`. Older Turing fits
without an explicit adaptation count remain `:not_recorded` even with zero
requested warmup. These events do not
change retained-draw warnings, R-hat/ESS or posterior summaries. A computed
section means reporting succeeded, not that adaptation passed a quality rule.
Older saved reports without this section remain readable without adding rows.
DFF sections default to the count-weighted additive projection. Set
`dff_adjustment=:observed_margins` only to reproduce the historical screen;
see [`dff_report`](@ref) for assignment support and uncertainty limits.

`reporting` is an optional named tuple for the common category, agreement,
named reliability-cohort, classification, ranking, observed-score alpha and ICC sections. It preserves explicit identities/targets,
all retained draws for posterior quantities, warnings and section failures in public/Markdown/JSON/bundle
output. Omitting it keeps previous report behavior. See the Saved-fit Reporting
API guide for its request fields and uncertainty definitions. Completeness is
execution status, not scientific or numerical acceptance. The alpha and ICC sections
use observed ratings, not posterior draws, and supply no SE or interval.
Generalized fits accept `include_effective_slopes=true` for a separate
joint-draw adjacent-logit slope section with credible intervals and endpoint MCSE.
It uses every retained draw, preserves whole-fit warnings and needs no predictive RNG.
The default is false; no historical section or fitted prior is replaced.
"""
function fit_report(fit::_ModelComparisonFit;
        view::Symbol = :full,
        reporting = nothing,
        include_prior_predictive::Bool = false,
        prior_predictive_ndraws::Int = 100,
        prior_predictive_rng::AbstractRNG = Random.default_rng(),
        include_posterior_predictive::Bool = true,
        include_grouped_predictive::Bool = true,
        predictive_interval::Real = 0.9,
        include_category_functioning::Bool = fit isa MFRMFit,
        category_functioning_interval::Real = 0.95,
        category_functioning_min_count::Int = 5,
        category_functioning_min_proportion::Real = 0.01,
        category_order_probability_threshold::Real = 0.8,
        include_rater_homogeneity::Bool = fit isa MFRMFit,
        rater_homogeneity_interval::Real = 0.95,
        rater_severity_rope = nothing,
        rater_rope_probability_threshold::Real = 0.95,
        rater_overlap_unit::Symbol = :person_item,
        rater_min_shared_units::Int = 1,
        ndraws::Union{Nothing,Int} = nothing,
        draw_indices = nothing,
        rng::AbstractRNG = Random.default_rng(),
        posterior_lower::Real = 0.025,
        posterior_upper::Real = 0.975,
        posterior_intervals = (0.66, 0.9, 0.95),
        posterior_reference::Real = 0.0,
        posterior_rope = nothing,
        posterior_rope_probability_threshold::Real = 0.95,
        include_direct_posterior::Bool = fit isa Union{GMFRMFit,MGMFRMFit},
        include_effective_slopes::Bool = false,
        include_calibration::Bool = true,
        calibration_target::Symbol = :expected_score,
        calibration_category = nothing,
        calibration_bins::Int = 10,
        calibration_interval::Real = 0.9,
        include_waic::Bool = true,
        waic_threshold::Real = 0.4,
        include_loo::Bool = true,
        loo_threshold::Real = 0.7,
        loo_tail_fraction::Real = 0.2,
        loo_min_tail_draws::Int = 5,
        include_dff::Bool = false,
        dff_terms = :validation,
        dff_interval::Real = 0.95,
        dff_min_n::Int = 1,
        dff_adjustment::Symbol = :assignment,
        dff_expected_score_practical_threshold = nothing,
        dff_logit_practical_threshold = nothing,
        dff_practical_probability_threshold::Real = 0.8,
        include_artifact::Bool = true,
        include_full_artifact::Bool = false,
        artifact_include_draws::Bool = false,
        artifact_include_log_posterior::Bool = artifact_include_draws,
        artifact_include_sampler_stats::Bool = false,
        artifact_include_environment::Bool = false,
        artifact_include_packages::Bool = false,
        split_chains::Bool = true,
        rhat_threshold::Real = 1.01,
        ess_threshold::Real = 400,
        on_section_error::Symbol = :capture,
        require_complete::Bool = false)
    view in (:full, :public) ||
        throw(ArgumentError("view must be :full or :public"))
    checked_on_error = _fit_report_on_section_error(on_section_error)
    reporting_request = _saved_reporting_request(fit, reporting)
    diagnostic_surface = diagnostics(fit;
        split_chains,
        rhat_threshold,
        ess_threshold)
    warmup = _fit_report_section(checked_on_error) do
        rows = sampler_diagnostics(fit; phase = :warmup)
        (; rows, n_rows = length(rows),
            interpretation = _FIT_REPORT_WARMUP_INTERPRETATION)
    end
    manifest = _model_manifest(fit, diagnostic_surface.summary)
    evidence_policy = _fit_evidence_artifact_schema_policy(
        :fit_report,
        manifest.status_policy;
        include_environment = artifact_include_environment)
    metadata = fit_metadata(fit)
    report_draw_indices = ndraws === nothing && draw_indices === nothing ?
        nothing : _posterior_draw_indices(fit, ndraws, draw_indices, rng)
    checked_dff_expected_score_practical_threshold = _dff_practical_threshold(
        dff_expected_score_practical_threshold,
        "dff_expected_score_practical_threshold",
    )
    checked_dff_logit_practical_threshold = _dff_practical_threshold(
        dff_logit_practical_threshold,
        "dff_logit_practical_threshold",
    )
    checked_dff_practical_probability_threshold =
        _dff_practical_probability_threshold(dff_practical_probability_threshold)

    include_effective_slopes && !(fit isa Union{GMFRMFit,MGMFRMFit}) && throw(ArgumentError(
        "include_effective_slopes requires a generalized GMFRM/MGMFRM fit"))
    posterior = _fit_report_section(checked_on_error) do
        rows = posterior_summary(fit;
            lower = posterior_lower,
            upper = posterior_upper,
            intervals = posterior_intervals,
            reference = posterior_reference,
            rope = posterior_rope,
            rope_probability_threshold = posterior_rope_probability_threshold)
        (;
            rows,
            n_rows = length(rows),
        )
    end

    direct_posterior = _fit_report_direct_posterior(fit;
        include_direct_posterior,
        posterior_lower,
        posterior_upper,
        posterior_intervals,
        posterior_reference,
        posterior_rope,
        posterior_rope_probability_threshold,
        on_section_error = checked_on_error)

    prior_predictive = _fit_report_prior_predictive(fit;
        include_prior_predictive,
        prior_predictive_ndraws,
        prior_predictive_rng,
        predictive_interval,
        include_grouped_predictive,
        on_section_error = checked_on_error)

    posterior_predictive = include_posterior_predictive ?
        _fit_report_section(checked_on_error) do
            check = posterior_predictive_check(fit;
                ndraws = nothing,
                draw_indices = report_draw_indices,
                rng)
            rows = predictive_check_summary(check;
                interval = predictive_interval,
                include_grouped = include_grouped_predictive)
            (;
                rows,
                n_rows = length(rows),
                draw_indices = hasproperty(check, :draw_indices) ?
                    copy(check.draw_indices) : nothing,
            )
        end :
        _fit_report_not_requested()

    category_functioning = _fit_report_category_functioning(fit;
        include_category_functioning,
        interval = category_functioning_interval,
        min_count = category_functioning_min_count,
        min_proportion = category_functioning_min_proportion,
        order_probability_threshold = category_order_probability_threshold,
        draw_indices = report_draw_indices,
        rng,
        on_section_error = checked_on_error,
    )

    rater_homogeneity = _fit_report_rater_homogeneity(fit;
        include_rater_homogeneity,
        interval = rater_homogeneity_interval,
        severity_rope = rater_severity_rope,
        rope_probability_threshold = rater_rope_probability_threshold,
        overlap_unit = rater_overlap_unit,
        min_shared_units = rater_min_shared_units,
        draw_indices = report_draw_indices,
        rng,
        on_section_error = checked_on_error,
    )

    calibration = include_calibration ?
        _fit_report_section(checked_on_error) do
            rows = calibration_table(fit;
                target = calibration_target,
                category = calibration_category,
                bins = calibration_bins,
                interval = calibration_interval,
                ndraws = nothing,
                draw_indices = report_draw_indices,
                rng)
            (;
                rows,
                n_rows = length(rows),
            )
        end :
        _fit_report_not_requested()

    waic_section = include_waic ?
        _fit_report_section(checked_on_error) do
            stat = waic(fit;
                ndraws = nothing,
                draw_indices = report_draw_indices,
                rng)
            diagnostic_rows = waic_diagnostics(fit;
                threshold = waic_threshold,
                ndraws = nothing,
                draw_indices = report_draw_indices,
                rng)
            (;
                stat,
                diagnostic_rows,
                n_diagnostic_rows = length(diagnostic_rows),
            )
        end :
        _fit_report_not_requested()

    loo_section = include_loo ?
        _fit_report_section(checked_on_error) do
            stat = loo(fit;
                ndraws = nothing,
                draw_indices = report_draw_indices,
                rng,
                pareto_k_threshold = loo_threshold,
                tail_fraction = loo_tail_fraction,
                min_tail_draws = loo_min_tail_draws)
            diagnostic_rows = loo_diagnostics(fit;
                threshold = loo_threshold,
                ndraws = nothing,
                draw_indices = report_draw_indices,
                rng,
                tail_fraction = loo_tail_fraction,
                min_tail_draws = loo_min_tail_draws)
            (;
                stat,
                diagnostic_rows,
                n_diagnostic_rows = length(diagnostic_rows),
            )
        end :
        _fit_report_not_requested()

    dff = _fit_report_dff(fit;
        include_dff,
        dff_terms,
        dff_interval,
        dff_min_n,
        dff_adjustment,
        dff_expected_score_practical_threshold =
            checked_dff_expected_score_practical_threshold,
        dff_logit_practical_threshold =
            checked_dff_logit_practical_threshold,
        dff_practical_probability_threshold =
            checked_dff_practical_probability_threshold,
        ndraws = nothing,
        draw_indices = report_draw_indices,
        rng,
        on_section_error = checked_on_error)

    prior_policy = _fit_report_prior_policy(fit)
    pooling_policy = _fit_report_pooling_policy(fit)
    mcmc_budget_guidance =
        _fit_report_mcmc_budget_guidance(fit, metadata, diagnostic_surface)
    fixed_coordinates = _fit_report_fixed_coordinates(
        fit,
        manifest,
        checked_on_error,
    )
    rating_design = _fit_report_section(checked_on_error) do
        audit = manifest.rating_design
        rows = collect(audit.rows)
        (;
            schema = audit.schema,
            rows,
            n_rows = length(rows),
            summary = audit.summary,
            audit,
        )
    end

    q_matrix = fit.design.spec.family === :mgmfrm ?
        _fit_report_section(checked_on_error) do
            validation = manifest.spec.q_matrix_validation
            rows = collect(validation.rows)
            raw_parameterization =
                hasproperty(manifest.design, :raw_parameterization) ?
                manifest.design.raw_parameterization :
                nothing
            confirmatory_candidate =
                raw_parameterization !== nothing &&
                    hasproperty(raw_parameterization, :confirmatory_candidate) ?
                raw_parameterization.confirmatory_candidate :
                nothing
            gauge_rows = confirmatory_candidate !== nothing ?
                collect(confirmatory_candidate.gauge_rows) :
                NamedTuple[]
            sign_positive_rules = confirmatory_candidate !== nothing ?
                collect(confirmatory_candidate.sign_positive_rules) :
                NamedTuple[]
            blocked_alternatives =
                confirmatory_candidate !== nothing &&
                    hasproperty(confirmatory_candidate, :experimental_public_api_decision) ?
                collect(confirmatory_candidate.experimental_public_api_decision.rejected_public_options) :
                NamedTuple[]
            initialization_policy =
                hasproperty(fit.diagnostic_surface, :initialization_policy) ?
                fit.diagnostic_surface.initialization_policy :
                nothing
            initialization_rows = _mgmfrm_initialization_rows(initialization_policy)
            fixed_q_invariance_rows =
                _mgmfrm_fixed_q_invariance_rows(fit.design, fit.diagnostic_surface;
                    prior = fit.prior)
            (;
                schema = validation.schema,
                q_matrix = validation.q_matrix,
                dimension_labels = validation.dimension_labels,
                cross_loading_policy = validation.cross_loading_policy,
                rows,
                n_rows = length(rows),
                gauge_rows,
                n_gauge_rows = length(gauge_rows),
                sign_positive_rules,
                n_sign_positive_rules = length(sign_positive_rules),
                blocked_alternatives,
                n_blocked_alternatives = length(blocked_alternatives),
                initialization_policy,
                initialization_rows,
                n_initialization_rows = length(initialization_rows),
                fixed_q_invariance_rows,
                n_fixed_q_invariance_rows = length(fixed_q_invariance_rows),
                identification = validation.identification,
                design_prior_scope = :source_reference_not_resolved_fit_prior,
                summary = validation.summary,
                validation,
            )
        end :
        _fit_report_not_requested()

    artifact = include_artifact ?
        _fit_report_section(checked_on_error) do
            value = fit_artifact(fit;
                include_draws = artifact_include_draws,
                include_log_posterior = artifact_include_log_posterior,
                include_sampler_stats = artifact_include_sampler_stats,
                include_environment = artifact_include_environment,
                include_packages = artifact_include_packages,
                split_chains,
                rhat_threshold,
                ess_threshold)
            (;
                schema = value.schema,
                content_hash = value.content_hash,
                archive_manifest = value.archive_manifest,
                artifact = include_full_artifact ? value : nothing,
            )
        end :
        _fit_report_not_requested()

    report = (;
        schema = "bayesianmgmfrm.fit_report.v1",
        object = :fit_report,
        created_at = string(now()),
        family = fit.design.spec.family,
        thresholds = fit.design.spec.thresholds,
        dimensions = fit.design.spec.dimensions,
        dimension_labels = copy(fit.design.spec.dimension_labels),
        estimation_status = fit.design.spec.estimation_status,
        status_policy = manifest.status_policy,
        evidence_artifact_schema_policy = evidence_policy,
        report_policy = (;
            include_prior_predictive,
            include_posterior_predictive,
            include_grouped_predictive,
            predictive_interval = Float64(predictive_interval),
            include_category_functioning,
            category_functioning_interval =
                Float64(category_functioning_interval),
            category_functioning_min_count,
            category_functioning_min_proportion =
                Float64(category_functioning_min_proportion),
            category_order_probability_threshold =
                Float64(category_order_probability_threshold),
            include_rater_homogeneity,
            rater_homogeneity_interval =
                Float64(rater_homogeneity_interval),
            rater_severity_rope,
            rater_rope_probability_threshold =
                Float64(rater_rope_probability_threshold),
            rater_overlap_unit,
            rater_min_shared_units,
            ndraws,
            draw_indices = draw_indices === nothing ? nothing : collect(draw_indices),
            resolved_draw_indices = report_draw_indices === nothing ?
                nothing : collect(report_draw_indices),
            posterior_intervals,
            include_direct_posterior,
            include_calibration,
            calibration_target,
            calibration_category,
            calibration_bins,
            calibration_interval = Float64(calibration_interval),
            include_waic,
            waic_threshold = Float64(waic_threshold),
            include_loo,
            loo_threshold = Float64(loo_threshold),
            loo_tail_fraction = Float64(loo_tail_fraction),
            loo_min_tail_draws,
            include_dff,
            dff_terms,
            dff_interval = Float64(dff_interval),
            dff_min_n,
            dff_adjustment,
            dff_expected_score_practical_threshold =
                checked_dff_expected_score_practical_threshold,
            dff_logit_practical_threshold =
                checked_dff_logit_practical_threshold,
            dff_practical_probability_threshold =
                checked_dff_practical_probability_threshold,
            include_artifact,
            include_full_artifact,
            on_section_error = checked_on_error,
            require_complete,
        ),
        metadata,
        manifest,
        model_surface_audit = manifest.model_surface_audit,
        rating_design,
        fixed_coordinates,
        q_matrix,
        diagnostics = diagnostic_surface,
        warmup,
        mcmc_budget_guidance,
        prior_policy,
        pooling_policy,
        prior_predictive,
        posterior,
        direct_posterior,
        posterior_predictive,
        category_functioning,
        rater_homogeneity,
        calibration,
        waic = waic_section,
        loo = loo_section,
        dff,
        artifact,
    )
    if include_effective_slopes
        report = merge(report, (; effective_slopes=_generalized_slope_report(fit;
            lower=posterior_lower, upper=posterior_upper, on_section_error=checked_on_error)))
    end
    report = _with_saved_reporting(report, fit, reporting_request, checked_on_error)
    health = fit_report_health(report)
    report = merge(report, (;
        report_status = health.status,
        report_health = health,
    ))
    require_complete && _require_complete_fit_report(report, :fit_report)
    return view === :full ? report : fit_report_public(report)
end

function _json_export_array(value::AbstractArray)
    if ndims(value) == 1
        return [_json_export_value(item) for item in value]
    elseif ndims(value) == 2
        return [[_json_export_value(value[i, j]) for j in axes(value, 2)]
                for i in axes(value, 1)]
    end
    return Dict{String,Any}(
        "shape" => collect(size(value)),
        "values" => [_json_export_value(item) for item in vec(value)],
    )
end

function _json_export_number(value::Number)
    if value isa AbstractFloat
        return isfinite(value) ? Float64(value) : string(value)
    elseif value isa Integer
        return value
    elseif value isa Real
        return isfinite(value) ? Float64(value) : string(value)
    end
    return string(value)
end

function _json_export_value(value)
    if value isa NamedTuple
        return Dict{String,Any}(
            String(name) => _json_export_value(getproperty(value, name))
            for name in keys(value)
        )
    elseif value isa AbstractDict
        return Dict{String,Any}(
            string(key) => _json_export_value(item)
            for (key, item) in value
        )
    elseif value isa Tuple
        return [_json_export_value(item) for item in value]
    elseif value isa AbstractArray
        return _json_export_array(value)
    elseif value isa Symbol
        return String(value)
    elseif value isa AbstractString
        return String(value)
    elseif value === missing || value === nothing
        return nothing
    elseif value isa Bool
        return value
    elseif value isa Number
        return _json_export_number(value)
    end
    return string(value)
end

function _json_hash_value(value; exact_integers::Bool = false)
    if value isa NamedTuple
        return NamedTuple{keys(value)}(
            Tuple(_json_hash_value(getproperty(value, name); exact_integers) for name in keys(value)),
        )
    elseif value isa AbstractDict
        return Dict{Any,Any}(
            key => _json_hash_value(item; exact_integers)
            for (key, item) in value
        )
    elseif value isa Tuple
        return map(item -> _json_hash_value(item; exact_integers), value)
    elseif value isa AbstractArray
        return [_json_hash_value(item; exact_integers) for item in value]
    elseif value isa Bool
        return value
    elseif exact_integers && value isa Integer
        # JSON does not retain signedness or bit width; canonicalize to exact decimal.
        return BigInt(value)
    elseif value isa Real
        return isfinite(value) ? Float64(value) : string(value)
    elseif value isa Number
        return string(value)
    end
    return value
end

const _FIT_REPORT_EXACT_JSON_CANONICALIZATION = :cache_stable_string_exact_integers_v1

function _fit_report_export_canonicalization(schema)
    schema == "bayesianmgmfrm.fit_report_export.v1" && return :cache_stable_string
    schema == "bayesianmgmfrm.fit_report_export.v2" &&
        return _FIT_REPORT_EXACT_JSON_CANONICALIZATION
    throw(ArgumentError("unsupported fit report export schema: $schema"))
end

function _fit_report_json_hash_record(payload;
        canonicalization::Symbol = :cache_stable_string)
    canonicalization in (:cache_stable_string, _FIT_REPORT_EXACT_JSON_CANONICALIZATION) ||
        throw(ArgumentError("unsupported fit report JSON hash canonicalization"))
    hash_payload = _json_hash_value(_artifact_hash_payload(payload);
        exact_integers = canonicalization === _FIT_REPORT_EXACT_JSON_CANONICALIZATION)
    canonical = _cache_stable_string(hash_payload)
    return (;
        algorithm = :sha256,
        value = bytes2hex(sha256(IOBuffer(canonical))),
        scope = :json_report_without_hash_metadata,
        canonicalization,
        n_canonical_bytes = sizeof(canonical),
    )
end

function _fit_report_export_record(report;
        label = nothing,
        source_path = nothing)
    _check_fit_report_payload(report)
    json_report = _json_export_value(report)
    location = source_path === nothing ? NamedTuple() : (;
        source_path = String(source_path),
    )
    return merge((;
        schema = "bayesianmgmfrm.fit_report_export.v2",
        object = :fit_report_export,
        created_at = string(now()),
        label = label === nothing ? missing : label,
    ), location, (;
        serialization = (;
            format = :json,
            writer = :JSON3,
            portability = :cross_tool_json_payload,
            missing_values = :json_null,
            nonfinite_numbers = :string,
        ),
        report_schema = _report_lookup(report, :schema, missing),
        report_object = _report_symbol_value(_report_lookup(report, :object, missing)),
        report_content_hash = _fit_report_content_hash_record(report),
        json_content_hash = _fit_report_json_hash_record(json_report;
            canonicalization = _FIT_REPORT_EXACT_JSON_CANONICALIZATION),
        report = json_report,
    ))
end

"""
    save_fit_report(path, report; overwrite = false, label = nothing,
        require_complete = false)
    save_fit_report(path, fit; overwrite = false, label = nothing,
        require_complete = false, kwargs...)

Write a `fit_report` bundle to a JSON export record at `path`. Passing a fit
object first builds `fit_report(fit; kwargs...)`. The saved record includes the
original report content hash and a JSON-payload hash that [`load_fit_report`](@ref)
verifies by default. Set `require_complete = true` to reject a report containing
any captured section error before writing.

New exports use envelope v2 and preserve exact integers in the JSON-payload
checksum. Older readers that accept only v1 cannot open these new exports.
"""
function save_fit_report(path::AbstractString,
        report;
        overwrite::Bool = false,
        label = nothing,
        require_complete::Bool = false)
    require_complete && _require_complete_fit_report(report, :save_fit_report)
    isfile(path) && !overwrite &&
        throw(ArgumentError("fit report export already exists at $path; pass overwrite = true to replace it"))
    record = _fit_report_export_record(report;
        label,
        source_path = _is_public_fit_report(report) ? nothing : path)
    mkpath(dirname(path))
    open(path, "w") do io
        JSON3.write(io, _json_export_value(record))
        write(io, "\n")
    end
    return record
end

function save_fit_report(path::AbstractString,
        fit::_ModelComparisonFit;
        overwrite::Bool = false,
        label = nothing,
        require_complete::Bool = false,
        kwargs...)
    report = fit_report(fit; require_complete, kwargs...)
    return save_fit_report(path, report;
        overwrite,
        label,
        require_complete)
end

function _check_fit_report_export_hash_record(record,
        field::AbstractString,
        path::AbstractString,
        expected_scope::AbstractString;
        canonicalization::Symbol = :cache_stable_string)
    return _check_fit_report_hash_record(record, Symbol(field),
        "fit report export at $path";
        expected_scope = Symbol(expected_scope),
        expected_canonicalization = canonicalization)
end

function _check_fit_report_export_record(record, path)
    record isa AbstractDict ||
        throw(ArgumentError("fit report export at $path does not contain a JSON object"))
    canonicalization = _fit_report_export_canonicalization(get(record, "schema", nothing))
    get(record, "object", nothing) == "fit_report_export" ||
        throw(ArgumentError("fit report export at $path has an unsupported object"))
    get(record, "report", nothing) isa AbstractDict ||
        throw(ArgumentError("fit report export at $path does not contain a report object"))
    report = record["report"]
    report_schema = get(report, "schema", nothing)
    report_object = get(report, "object", nothing)
    isequal(get(record, "report_schema", nothing), report_schema) ||
        throw(ArgumentError("fit report export at $path has inconsistent report schemas"))
    isequal(get(record, "report_object", nothing), report_object) ||
        throw(ArgumentError("fit report export at $path has inconsistent report objects"))
    _check_fit_report_payload(report)
    if report_schema == _FIT_REPORT_PUBLIC_SCHEMA
        haskey(record, "source_path") &&
            throw(ArgumentError("public fit report export at $path contains source_path"))
    end
    report_hash_scope = String(_fit_report_content_hash_scope(report_schema))
    _check_fit_report_export_hash_record(record, "report_content_hash", path,
        report_hash_scope)
    _check_fit_report_export_hash_record(record, "json_content_hash", path,
        "json_report_without_hash_metadata"; canonicalization)
    if report_schema == _FIT_REPORT_PUBLIC_SCHEMA
        _fit_report_hash_record_matches_actual(record, :report_content_hash,
            _public_fit_report_content_hash_record(report),
            "public fit report export at $path";
            expected_scope = :public_json_without_top_level_content_hash,
            expected_canonicalization = :cache_stable_string)
    end
    return record
end

function _verify_fit_report_export_record(record, path)
    canonicalization = _fit_report_export_canonicalization(record["schema"])
    _fit_report_hash_record_matches_actual(record, :json_content_hash,
        _fit_report_json_hash_record(record["report"]; canonicalization),
        "fit report export at $path";
        expected_scope = :json_report_without_hash_metadata,
        expected_canonicalization = canonicalization)
    return record
end

"""
    load_fit_report(path; verify_hash = true, return_record = false,
        require_complete = false)

Load a JSON fit-report export written by [`save_fit_report`](@ref). The JSON
payload hash is verified by default, and the export/hash metadata shape is
always checked. The report payload is returned as `Dict{String,Any}` /
`Vector{Any}` data; set `return_record = true` to inspect the export metadata
and hash records as well.

Both v1 and v2 export envelopes are readable. V1 retains its original
floating-point number normalization; v2 checks integer values exactly.

Set `require_complete = true` to verify report completeness after the payload
and hashes have been checked.
"""
function load_fit_report(path::AbstractString;
        verify_hash::Bool = true,
        return_record::Bool = false,
        require_complete::Bool = false)
    isfile(path) ||
        throw(ArgumentError("fit report export does not exist at $path"))
    record = _read_json_dict(path, "fit report export")
    record = _check_fit_report_export_record(record, path)
    verify_hash && _verify_fit_report_export_record(record, path)
    require_complete &&
        _require_complete_fit_report(record["report"], :load_fit_report)
    return return_record ? record : record["report"]
end

const _FIT_REPORT_LOOKUP_MISSING = Ref(:fit_report_lookup_missing)
const _FIT_REPORT_SECTION_ORDER = (
    :diagnostics,
    :warmup,
    :rating_design,
    :fixed_coordinates,
    :category_functioning,
    :rater_homogeneity,
    :category_report,
    :score_information,
    :posterior_reliability,
    :posterior_classification,
    :posterior_ranking,
    :rater_agreement,
    :krippendorff_alpha,
    :intraclass_correlation,
    :q_matrix,
    :mcmc_budget_guidance,
    :prior_policy,
    :pooling_policy,
    :prior_predictive,
    :posterior,
    :direct_posterior,
    :effective_slopes,
    :posterior_predictive,
    :calibration,
    :waic,
    :loo,
    :dff,
    :artifact,
)
const _FIT_REPORT_ROW_FIELD_ORDER = (
    :rows,
    :usage_rows,
    :threshold_rows,
    :contrast_rows,
    :warning_rows,
    :diagnostic_rows,
    :sampler_rows,
    :parameter_rows,
    :block_rows,
    :gauge_rows,
    :sign_positive_rules,
    :blocked_alternatives,
    :initialization_rows,
    :fixed_q_invariance_rows,
)

function _report_key_symbol(key::Symbol)
    return key
end

function _report_key_symbol(key::AbstractString)
    return Symbol(key)
end

function _report_key_symbol(key)
    throw(ArgumentError("fit report keys must be Symbols or strings; got $(typeof(key))"))
end

function _report_lookup(container::NamedTuple, key::Symbol, default)
    return key in keys(container) ? getproperty(container, key) : default
end

function _report_lookup(container::AbstractDict, key::Symbol, default)
    if haskey(container, key)
        return container[key]
    end
    string_key = String(key)
    return haskey(container, string_key) ? container[string_key] : default
end

function _report_lookup(container, key::Symbol, default)
    return default
end

function _report_lookup(container, key, default)
    return _report_lookup(container, _report_key_symbol(key), default)
end

function _report_keys(container::NamedTuple)
    return collect(keys(container))
end

function _report_keys(container::AbstractDict)
    return unique!([_report_key_symbol(key) for key in keys(container)])
end

function _report_keys(container)
    return Symbol[]
end

const _FIT_REPORT_FULL_SCHEMA = "bayesianmgmfrm.fit_report.v1"
const _FIT_REPORT_PUBLIC_SCHEMA = "bayesianmgmfrm.fit_report_public.v1"

function _check_fit_report_payload(report)
    (report isa NamedTuple || report isa AbstractDict) ||
        throw(ArgumentError("expected a fit_report payload as a NamedTuple or Dict"))
    schema = _report_lookup(report, :schema, _FIT_REPORT_LOOKUP_MISSING)
    schema in (_FIT_REPORT_FULL_SCHEMA, _FIT_REPORT_PUBLIC_SCHEMA) ||
        throw(ArgumentError(
            "expected a bayesianmgmfrm.fit_report.v1 or " *
            "bayesianmgmfrm.fit_report_public.v1 payload"))
    schema == _FIT_REPORT_PUBLIC_SCHEMA &&
        _assert_public_fit_report_language(report)
    recorded_status = _report_lookup(report, :report_status,
        _FIT_REPORT_LOOKUP_MISSING)
    recorded_health = _report_lookup(report, :report_health,
        _FIT_REPORT_LOOKUP_MISSING)
    if recorded_status !== _FIT_REPORT_LOOKUP_MISSING ||
            recorded_health !== _FIT_REPORT_LOOKUP_MISSING
        _check_recorded_fit_report_health(
            report,
            _derive_fit_report_health(report),
        )
    end
    return report
end

function _check_full_fit_report_payload(report)
    _check_fit_report_payload(report)
    schema = _report_lookup(report, :schema, _FIT_REPORT_LOOKUP_MISSING)
    schema == _FIT_REPORT_FULL_SCHEMA ||
        throw(ArgumentError("expected a bayesianmgmfrm.fit_report.v1 payload"))
    return report
end

_is_public_fit_report(report) =
    _report_lookup(report, :schema, _FIT_REPORT_LOOKUP_MISSING) ==
    _FIT_REPORT_PUBLIC_SCHEMA

const _PUBLIC_FIT_REPORT_OMITTED = Ref(:public_fit_report_omitted)

const _PUBLIC_FIT_REPORT_HIDDEN_FIELDS = Set((
    :archive_manifest,
    :artifact,
    :audit,
    :blocked_alternatives,
    :blocked_option,
    :blocker,
    :cache_path,
    :caveat_docs_artifact,
    :chain_type,
    :data_signature,
    :environment,
    :evidence,
    :evidence_artifact_schema_policy,
    :experimental_public,
    :fit_ready,
    :fixture_provenance,
    :guarded_local_fit,
    :initialization_policy,
    :internal_sampler_diagnostic_constructor,
    :internal_target_constructor,
    :manifest,
    :manuscript_claims_allowed,
    :model_surface_audit,
    :next_gate,
    :object,
    :output_path,
    :package_default_change,
    :publication_or_registration_action,
    :public_fit,
    :public_claim_allowed,
    :raw_prior_control_manifest,
    :report_policy,
    :report_bundle_path,
    :schema,
    :scope,
    :source_path,
    :stable_public,
    :status_policy,
    :supported_surface,
    :turing_model,
    :validation,
))

const _PUBLIC_FIT_REPORT_TOP_LEVEL_SECTIONS = (
    :metadata,
    :rating_design,
    :fixed_coordinates,
    :category_functioning,
    :rater_homogeneity,
    :category_report,
    :score_information,
    :posterior_reliability,
    :posterior_classification,
    :posterior_ranking,
    :rater_agreement,
    :krippendorff_alpha,
    :intraclass_correlation,
    :q_matrix,
    :diagnostics,
    :warmup,
    :mcmc_budget_guidance,
    :prior_policy,
    :pooling_policy,
    :prior_predictive,
    :posterior,
    :direct_posterior,
    :effective_slopes,
    :posterior_predictive,
    :calibration,
    :waic,
    :loo,
    :dff,
    :artifact,
)

const _PUBLIC_FIT_REPORT_UNSAFE_TEXT_PATTERNS = (
    r"(?i)\bprivate[\s_-]+(?:reference|result|correlated)\b",
    r"(?i)\binternal(?![\s_-]+consistency\b)(?:[\s_-]+[A-Za-z0-9_-]+)*\b",
    r"(?<![\p{L}\p{N}_])_+[\p{L}][\p{L}\p{N}_!]*",
    r"(?:file://|(?<![A-Za-z0-9:/])/(?:Users|home|tmp|private/(?:tmp|var/folders)|var/(?:folders|tmp)|workspace|workspaces|Volumes|mnt)(?:/|\b)|(?<![A-Za-z0-9])[A-Za-z]:[\\/]+|\\\\[^\\/\s]+[\\/]+[^\\/\s]+)",
    r"(?:test/fixtures/|scripts/generate_|artifacts/(?:uto_style|publication_grade))",
    r"(?i)\b(?:source[\s_-]?fixture[A-Za-z0-9_]*|fixture[\s_-]?only|fixture[\s_-]?provenance|promotion[\s_-]?candidate|guarded[\s_-]?local[\s_-]?entrypoint|guarded[\s_-]?local[\s_-]?fit|experimental_public|next[\s_-]?gate|blocked[\s_-]?option|supported[\s_-]?surface|candidate[\s_-]?gates|caveat[\s_-]?docs[\s_-]?artifact|internal[\s_-]?target[\s_-]?constructor|internal[\s_-]?sampler[\s_-]?diagnostic[\s_-]?constructor|publication[\s_-]?or[\s_-]?registration[\s_-]?action|manual[\s_-]?publication[\s_-]?or[\s_-]?registration[\s_-]?by[\s_-]?user[\s_-]?only|manuscript[\s_-]?claims[\s_-]?allowed|public[\s_-]?claim[\s_-]?allowed|package[\s_-]?default[\s_-]?change)\b",
    r"(?i)\b(?:development[\s_-]+ledgers?|registry[\s_-]+maintenance|release[\s_-]+control|worktree[\s_-]+checking|release[\s_-]+handoff|CI[\s_-]+rendering)\b",
    r"(?i)\b(?:until\s+the\s+package\s+is\s+registered\s+in\s+julia\s+general|after\s+general\s+registration|pre[\s-]+registration|promotion[\s-]+candidate|manual\s+public[\s-]+scope|(?:manual[\s-]+)?local[\s-]+only)\b",
    r"(?i)(?:\brelease_gate_check\b|\brelease_scope_summary\b|\bcase_study_provenance_manifest\b|\bevidence_artifact_schema_policy\b|\bGeneral\s+AutoMerge\b|\bRegistrator\b|@JuliaRegistrator|\bregistration\s+handoff\b|\bfixture[\s-]+SHA\b|--read-local-artifacts|\bmethod[\s-]+wiring\b|\blocal\s+runner\b|\bimplementation\s+checklist\b|\bexecution\s+prompt\s+pack\b|\bcurrent\s+branch\s+status\b)",
)

const _PUBLIC_FIT_REPORT_USER_VALUE_FIELDS = Set((
    :category,
    :category_levels,
    :cell,
    :column_levels,
    :contrast,
    :dimension_label,
    :dimension_labels,
    :dataset_id,
    :direct_parameter_names,
    :facet,
    :focal_level,
    :group,
    :item,
    :label,
    :level,
    :model,
    :models,
    :optional_facets,
    :observation_id,
    :observation_ids,
    :problem_observation_ids,
    :parameter,
    :parameter_name,
    :parameter_names,
    :person,
    :rater,
    :reference_level,
    :row_levels,
    :step_path,
    :term,
    :threshold_path,
    :cohort_id,
    :profile_id,
    :id,
    :parameters,
    :response_id,
    :response_ids,
    :unmatched_observation_ids,
    :observation_a,
    :observation_b,
    :rater_a,
    :rater_b,
    :empirical_zero_variance_parameters,
))

function _public_fit_report_user_value_field(field::Symbol)
    field in _PUBLIC_FIT_REPORT_USER_VALUE_FIELDS && return true
    name = lowercase(String(field))
    return endswith(name, "_label") || endswith(name, "_labels") ||
        endswith(name, "_level") || endswith(name, "_levels")
end

function _public_fit_report_field_allowed(field::Symbol)
    field in _PUBLIC_FIT_REPORT_HIDDEN_FIELDS && return false
    name = lowercase(String(field))
    startswith(name, "internal_") && return false
    startswith(name, "raw_") && return false
    name in ("artifact_path", "file_path", "repository_path") && return false
    for fragment in (
            "fixture", "next_gate", "blocked_option", "blocked_alternative",
            "supported_surface", "publication", "registration", "claim",
            "promotion", "package_default", "candidate", "constructor",
            "caveat_docs", "generator", "command", "public_fit",
            "public_exposure", "release_control")
        occursin(fragment, name) && return false
    end
    return true
end

function _public_fit_report_projection_field_allowed(field::Symbol,
        path::Tuple)
    field === :audit && path == (:rating_design, :rows) && return true
    field === :evidence && path == (:evidence_rows,) && return true
    return _public_fit_report_field_allowed(field)
end

function _public_fit_report_sanitized_text(value::AbstractString)
    text = String(value)
    for (source, replacement) in (
            "guarded_experimental_public" => "experimental",
            "experimental_public" => "experimental",
            "guarded_local_fit" => "experimental",
            "fit_supported" => "supported",
            "specified_only" => "not_supported",
            "stable_public" => "supported")
        text = replace(text, source => replacement)
    end
    any(pattern -> occursin(pattern, text),
        _PUBLIC_FIT_REPORT_UNSAFE_TEXT_PATTERNS) &&
        return _PUBLIC_FIT_REPORT_OMITTED
    return text
end

_public_fit_report_user_text_scalar(value) =
    value isa Symbol || value isa AbstractString

function _public_fit_report_child_preserves_user_text(value,
        preserve_user_text::Bool)
    return preserve_user_text && _public_fit_report_user_text_scalar(value)
end

function _public_fit_report_project_value(value;
        preserve_user_text::Bool = false,
        path::Tuple = ())
    if value isa NamedTuple
        pairs = Pair{Symbol,Any}[]
        for field in keys(value)
            _public_fit_report_projection_field_allowed(field, path) || continue
            projected = _public_fit_report_project_value(
                getproperty(value, field);
                preserve_user_text =
                    _public_fit_report_user_value_field(field),
                path = (path..., field),
            )
            projected === _PUBLIC_FIT_REPORT_OMITTED && continue
            push!(pairs, field => projected)
        end
        return (; pairs...)
    elseif value isa AbstractDict
        projected = Dict{String,Any}()
        for (key, item) in value
            field = _report_key_symbol(key)
            _public_fit_report_projection_field_allowed(field, path) || continue
            projected_item = _public_fit_report_project_value(item;
                preserve_user_text =
                    _public_fit_report_user_value_field(field),
                path = (path..., field))
            projected_item === _PUBLIC_FIT_REPORT_OMITTED && continue
            projected[String(field)] = projected_item
        end
        return projected
    elseif value isa Tuple
        projected = Any[]
        for item in value
            projected_item = _public_fit_report_project_value(item;
                preserve_user_text =
                    _public_fit_report_child_preserves_user_text(
                        item, preserve_user_text),
                path)
            push!(projected, projected_item === _PUBLIC_FIT_REPORT_OMITTED ?
                missing : projected_item)
        end
        return Tuple(projected)
    elseif value isa AbstractArray
        if ndims(value) == 1
            projected = Any[]
            for item in value
                projected_item = _public_fit_report_project_value(item;
                    preserve_user_text =
                        _public_fit_report_child_preserves_user_text(
                            item, preserve_user_text),
                    path)
                push!(projected, projected_item === _PUBLIC_FIT_REPORT_OMITTED ?
                    missing : projected_item)
            end
            return projected
        end
        return map(value) do item
            projected_item = _public_fit_report_project_value(item;
                preserve_user_text =
                    _public_fit_report_child_preserves_user_text(
                        item, preserve_user_text),
                path)
            projected_item === _PUBLIC_FIT_REPORT_OMITTED ? missing : projected_item
        end
    elseif value isa Symbol
        preserve_user_text && return value
        projected = _public_fit_report_sanitized_text(String(value))
        return projected === _PUBLIC_FIT_REPORT_OMITTED ? projected : Symbol(projected)
    elseif value isa AbstractString
        preserve_user_text && return String(value)
        return _public_fit_report_sanitized_text(value)
    elseif value === missing || value === nothing || value isa Bool
        return value
    elseif value isa Number
        return _json_export_number(value)
    end
    return _PUBLIC_FIT_REPORT_OMITTED
end

const _PUBLIC_READER_HIDDEN_FIELDS = Set((
    :archive_manifest,
    :artifact,
    :artifacts,
    :blocked_alternatives,
    :blocked_claims,
    :blocked_option,
    :cache_path,
    :caveat_docs_artifact,
    :data_signature,
    :design_identity,
    :environment,
    :experimental_public,
    :file_path,
    :fit_ready,
    :fixture_provenance,
    :guarded_local_fit,
    :initialization_policy,
    :internal_sampler_diagnostic_constructor,
    :internal_target_constructor,
    :manifest,
    :manuscript_claims_allowed,
    :next_gate,
    :output_path,
    :package_default_change,
    :publication_or_registration_action,
    :public_claim_allowed,
    :public_fit,
    :raw_prior_control_manifest,
    :report_bundle_path,
    :report_policy,
    :repository_path,
    :scope,
    :source,
    :source_path,
    :stable_public,
    :status_policy,
    :supported_surface,
    :target,
    :turing_model,
))

function _public_reader_hidden_field(field::Symbol)
    field in _PUBLIC_READER_HIDDEN_FIELDS && return true
    name = lowercase(String(field))
    return startswith(name, "internal_") ||
        startswith(name, "private_") ||
        occursin("guarded", name) || occursin("fixture", name) ||
        occursin("hash", name) || occursin("fingerprint", name) ||
        occursin("digest", name) || occursin("signature", name)
end

function _public_reader_sanitized_text(value::AbstractString)
    text = String(value)
    for (source, replacement) in (
            "outside_guarded_local_mgmfrm_scope" =>
                "outside_fixed_q_confirmatory_mgmfrm_scope",
            "free_latent_correlation_blocked_for_guarded_candidate" =>
                "free_latent_correlation_not_supported",
            "fixed_q_identity_correlation_defines_candidate_gauge" =>
                "fixed_q_identity_correlation_defines_gauge",
            "guarded_mgmfrm_preview" =>
                "fixed_q_confirmatory_mgmfrm_preview",
            "public_mfrm_baseline_or_guarded_gmfrm_comparison" =>
                "mfrm_baseline_or_experimental_gmfrm_comparison",
            "blocked_broad_generalized_mgmfrm" =>
                "broader_generalized_mgmfrm_not_supported",
            "package_under_development" =>
                "package_specific_bayesian_workflow",
            "release_gate_check" => "scope_and_evidence_checks",
            "promotion_candidate" => "experimental_configuration",
            "guarded_experimental_public" => "experimental",
            "experimental_public" => "experimental",
            "guarded_local_fit" => "experimental",
            "fit_supported" => "supported",
            "stable_public" => "supported")
        text = replace(text, source => replacement)
    end
    text == "blocked" && return "not_supported"
    any(pattern -> occursin(pattern, text),
        _PUBLIC_FIT_REPORT_UNSAFE_TEXT_PATTERNS) &&
        return _PUBLIC_FIT_REPORT_OMITTED
    return text
end

function _public_reader_project_value(value;
        preserve_user_text::Bool = false,
        path::Tuple = ())
    if value isa NamedTuple
        pairs = Pair{Symbol,Any}[]
        for field in keys(value)
            _public_reader_hidden_field(field) && continue
            projected = _public_reader_project_value(
                getproperty(value, field);
                preserve_user_text = _public_fit_report_user_value_field(field),
                path = (path..., field),
            )
            projected === _PUBLIC_FIT_REPORT_OMITTED && continue
            push!(pairs, field => projected)
        end
        return (; pairs...)
    elseif value isa AbstractDict
        projected = Dict{String,Any}()
        for (key, item) in value
            field = _report_key_symbol(key)
            _public_reader_hidden_field(field) && continue
            projected_item = _public_reader_project_value(
                item;
                preserve_user_text = _public_fit_report_user_value_field(field),
                path = (path..., field),
            )
            projected_item === _PUBLIC_FIT_REPORT_OMITTED && continue
            projected[String(field)] = projected_item
        end
        return projected
    elseif value isa Tuple
        projected = Any[]
        for item in value
            projected_item = _public_reader_project_value(
                item;
                preserve_user_text =
                    _public_fit_report_child_preserves_user_text(
                        item,
                        preserve_user_text,
                    ),
                path,
            )
            push!(projected, projected_item === _PUBLIC_FIT_REPORT_OMITTED ?
                missing : projected_item)
        end
        return Tuple(projected)
    elseif value isa AbstractArray
        return map(value) do item
            projected_item = _public_reader_project_value(
                item;
                preserve_user_text =
                    _public_fit_report_child_preserves_user_text(
                        item,
                        preserve_user_text,
                    ),
                path,
            )
            projected_item === _PUBLIC_FIT_REPORT_OMITTED ? missing : projected_item
        end
    elseif value isa Symbol
        preserve_user_text && return value
        projected = _public_reader_sanitized_text(String(value))
        return projected === _PUBLIC_FIT_REPORT_OMITTED ? projected : Symbol(projected)
    elseif value isa AbstractString
        preserve_user_text && return String(value)
        return _public_reader_sanitized_text(value)
    elseif value === missing || value === nothing || value isa Bool
        return value
    elseif value isa Number
        return _json_export_number(value)
    end
    return _PUBLIC_FIT_REPORT_OMITTED
end

function _public_mgmfrm_initialization_rows(rows)
    return [row.policy in (:initial_raw_vector, :initial_direct_transform) ?
        merge(row, (value = missing,)) : row for row in rows]
end

function _public_mgmfrm_fixed_q_invariance_rows(rows)
    return map(rows) do row
        row.policy === :latent_correlation && return merge(row, (;
            note = :free_latent_correlation_not_supported,
        ))
        row.policy === :rotation && return merge(row, (;
            value = :not_supported,
            note = :fixed_q_identity_correlation_defines_gauge,
        ))
        row.policy === :exploratory_loading && return merge(row, (;
            status = :not_supported,
            note = :outside_fixed_q_confirmatory_mgmfrm_scope,
        ))
        return row
    end
end

function _public_reader_payload(payload;
        schema::AbstractString,
        family = nothing,
        stability = nothing)
    projected = _public_reader_project_value(payload)
    body = Pair{Symbol,Any}[]
    for field in keys(projected)
        field in (:schema, :family, :stability) && continue
        push!(body, field => getproperty(projected, field))
    end
    header = Pair{Symbol,Any}[:schema => String(schema)]
    family === nothing || push!(header, :family => family)
    stability === nothing || push!(header, :stability => stability)
    return (; header..., body...)
end

function _public_fit_report_status(value)
    status = _report_symbol_value(value)
    status in (:fit_supported, :stable_public, :supported) && return :supported
    status in (:experimental_public, :guarded_local_fit, :experimental) &&
        return :experimental
    status in (:specified_only, :blocked, :unsupported, :not_supported) &&
        return :not_supported
    return :unknown
end

function _public_fit_report_content_hash_record(report)
    if _report_lookup(report, :schema, _FIT_REPORT_LOOKUP_MISSING) ==
            _FIT_REPORT_FULL_SCHEMA
        return _fit_report_json_hash_record(_json_export_value(report))
    end
    payload = _json_export_value(report)
    delete!(payload, "content_hash")
    canonical = _cache_stable_string(_json_hash_value(payload))
    return (;
        algorithm = :sha256,
        value = bytes2hex(sha256(IOBuffer(canonical))),
        scope = :public_json_without_top_level_content_hash,
        canonicalization = :cache_stable_string,
        n_canonical_bytes = sizeof(canonical),
    )
end

_fit_report_content_hash_scope(schema) =
    schema == _FIT_REPORT_PUBLIC_SCHEMA ?
    :public_json_without_top_level_content_hash :
    :artifact_without_hash_metadata

function _fit_report_content_hash_record(report)
    return _is_public_fit_report(report) ?
        _public_fit_report_content_hash_record(report) :
        _artifact_content_hash_record(report)
end

function _public_fit_report_output_field_allowed(field::Symbol,
        path::Tuple)
    if isempty(path)
        return field in (
            :schema, :object, :created_at, :source_report, :family,
            :thresholds, :dimensions, :dimension_labels, :status,
            :report_status, :report_health, :content_hash,
        ) || field in _PUBLIC_FIT_REPORT_TOP_LEVEL_SECTIONS
    elseif path == (:source_report,)
        return field in (:schema, :content_hash)
    elseif path == (:content_hash,)
        return field in (
            :algorithm, :value, :scope, :canonicalization,
            :n_canonical_bytes,
        )
    end
    return _public_fit_report_projection_field_allowed(field, path)
end

function _assert_public_fit_report_value(value,
        path::Tuple = ();
        preserve_user_text::Bool = false)
    if value isa NamedTuple
        for field in keys(value)
            _public_fit_report_output_field_allowed(field, path) ||
                throw(ArgumentError(
                    "fit_report_public contains a repository-maintenance field"))
            _assert_public_fit_report_value(getproperty(value, field),
                (path..., field);
                preserve_user_text =
                    _public_fit_report_user_value_field(field))
        end
    elseif value isa AbstractDict
        for (key, item) in value
            field = _report_key_symbol(key)
            _public_fit_report_output_field_allowed(field, path) ||
                throw(ArgumentError(
                    "fit_report_public contains a repository-maintenance field"))
            _assert_public_fit_report_value(item, (path..., field);
                preserve_user_text =
                    _public_fit_report_user_value_field(field))
        end
    elseif value isa Tuple || value isa AbstractArray
        for item in value
            _assert_public_fit_report_value(item, path;
                preserve_user_text =
                    _public_fit_report_child_preserves_user_text(
                        item, preserve_user_text))
        end
    elseif (value isa Symbol || value isa AbstractString) && !preserve_user_text
        text = String(value)
        for pattern in _PUBLIC_FIT_REPORT_UNSAFE_TEXT_PATTERNS
            occursin(pattern, text) || continue
            throw(ArgumentError(
                "fit_report_public could not remove a private implementation detail"))
        end
    end
    return value
end

function _check_public_fit_report_hash(report)
    object = _report_symbol_value(_report_lookup(report, :object, missing))
    object === :fit_report_public ||
        throw(ArgumentError("invalid fit_report_public object label"))
    status = _report_symbol_value(_report_lookup(report, :status, missing))
    status isa Symbol &&
        status in (:supported, :experimental, :not_supported, :unknown) ||
        throw(ArgumentError("invalid fit_report_public status label"))
    report_status = _report_lookup(report, :report_status,
        _FIT_REPORT_LOOKUP_MISSING)
    report_status === _FIT_REPORT_LOOKUP_MISSING ||
        _report_symbol_value(report_status) in (:complete, :incomplete) ||
        throw(ArgumentError("invalid fit_report_public report_status label"))
    source_report = _report_lookup(report, :source_report, missing)
    isequal(_report_lookup(source_report, :schema, missing),
        _FIT_REPORT_FULL_SCHEMA) ||
        throw(ArgumentError("invalid fit_report_public source-report schema"))
    source_hash = _report_lookup(source_report, :content_hash, missing)
    source_hash isa AbstractString &&
        occursin(r"^[0-9a-f]{64}$", source_hash) ||
        throw(ArgumentError("fit_report_public source-report hash is missing"))
    hash_record = _report_lookup(report, :content_hash, missing)
    _report_symbol_value(_report_lookup(hash_record, :algorithm, missing)) === :sha256 ||
        throw(ArgumentError("invalid fit_report_public hash algorithm"))
    expected = _report_lookup(hash_record, :value, missing)
    actual = _public_fit_report_content_hash_record(report)
    expected isa AbstractString && occursin(r"^[0-9a-f]{64}$", expected) &&
        expected == actual.value ||
        throw(ArgumentError("fit_report_public content hash mismatch"))
    _report_symbol_value(_report_lookup(hash_record, :scope, missing)) ===
        actual.scope ||
        throw(ArgumentError("invalid fit_report_public hash scope"))
    _report_symbol_value(_report_lookup(hash_record, :canonicalization, missing)) ===
        actual.canonicalization ||
        throw(ArgumentError("invalid fit_report_public hash canonicalization"))
    isequal(_report_lookup(hash_record, :n_canonical_bytes, missing),
        actual.n_canonical_bytes) ||
        throw(ArgumentError("invalid fit_report_public hash byte count"))
    return report
end

function _assert_public_fit_report_language(report)
    _check_public_fit_report_hash(report)
    _assert_public_fit_report_value(report)
    return report
end

"""
    fit_report_public(report)
    fit_report_public(fit; kwargs...)

Return a reader-facing structured projection of a full `fit_report` payload.
The result uses schema `bayesianmgmfrm.fit_report_public.v1`, preserves model
results and diagnostic rows, normalizes support labels, and recursively omits
implementation-only fields and machine-specific paths. The complete
`bayesianmgmfrm.fit_report.v1` payload remains unchanged for compatibility and
reproducibility workflows.
User-supplied label values remain unchanged, nonfinite numeric values use
portable string representations, and the public content hash is normalized to
the JSON representation so it remains stable after save/load.

Passing a fit object first builds `fit_report(fit; view = :full, kwargs...)`.
The projection is idempotent and may also be applied to a JSON-loaded public
report.
"""
function fit_report_public(report)
    _check_fit_report_payload(report)
    if _is_public_fit_report(report)
        return _assert_public_fit_report_language(report)
    end
    _check_full_fit_report_payload(report)
    health = fit_report_health(report)
    section_pairs = Pair{Symbol,Any}[]
    for section in _PUBLIC_FIT_REPORT_TOP_LEVEL_SECTIONS
        value = _report_lookup(report, section, _FIT_REPORT_LOOKUP_MISSING)
        value === _FIT_REPORT_LOOKUP_MISSING && continue
        projected = _public_fit_report_project_value(value;
            path = (section,))
        projected === _PUBLIC_FIT_REPORT_OMITTED && continue
        push!(section_pairs, section => projected)
    end
    estimation_status = _report_lookup(report, :estimation_status, missing)
    status_policy = _report_lookup(report, :status_policy, missing)
    public_status_source = status_policy === missing ?
        estimation_status :
        _report_lookup(status_policy, :status_label, estimation_status)
    payload = merge((;
        schema = _FIT_REPORT_PUBLIC_SCHEMA,
        object = :fit_report_public,
        created_at = _public_fit_report_project_value(
            _report_lookup(report, :created_at, missing)),
        source_report = (;
            schema = _FIT_REPORT_FULL_SCHEMA,
            content_hash = _public_fit_report_content_hash_record(report).value,
        ),
        family = _public_fit_report_project_value(
            _report_lookup(report, :family, missing)),
        thresholds = _public_fit_report_project_value(
            _report_lookup(report, :thresholds, missing)),
        dimensions = _public_fit_report_project_value(
            _report_lookup(report, :dimensions, missing)),
        dimension_labels = _public_fit_report_project_value(
            _report_lookup(report, :dimension_labels, Any[]);
            preserve_user_text = true),
        status = _public_fit_report_status(public_status_source),
        report_status = health.status,
        report_health = _public_fit_report_project_value(
            health;
            path = (:report_health,)),
    ), (; section_pairs...))
    public_report = merge(payload, (;
        content_hash = _public_fit_report_content_hash_record(payload),
    ))
    return _assert_public_fit_report_language(public_report)
end

function fit_report_public(fit::_ModelComparisonFit; kwargs...)
    return fit_report_public(fit_report(fit; kwargs...))
end

function _report_status(section)
    status = _report_lookup(section, :status, missing)
    status === missing && return missing
    status isa Symbol && return status
    status isa AbstractString && return Symbol(status)
    return status
end

function _report_row_fields(section)
    fields = Symbol[]
    for field in _FIT_REPORT_ROW_FIELD_ORDER
        rows = _report_lookup(section, field, _FIT_REPORT_LOOKUP_MISSING)
        rows isa AbstractVector && push!(fields, field)
    end
    known = Set(fields)
    extra = Symbol[]
    for field in _report_keys(section)
        field in known && continue
        endswith(String(field), "_rows") || continue
        rows = _report_lookup(section, field, _FIT_REPORT_LOOKUP_MISSING)
        rows isa AbstractVector && push!(extra, field)
    end
    append!(fields, sort(extra; by = String))
    return fields
end

function _report_row_count(section, row_field::Symbol, rows)
    count_key = row_field == :rows ? :n_rows : Symbol("n_", String(row_field))
    count = _report_lookup(section, count_key, _FIT_REPORT_LOOKUP_MISSING)
    count isa Integer && count >= 0 && return Int(count)
    return length(rows)
end

function _report_total_row_count(section, row_fields)
    total = 0
    for row_field in row_fields
        rows = _report_lookup(section, row_field, _FIT_REPORT_LOOKUP_MISSING)
        rows isa AbstractVector || continue
        total += _report_row_count(section, row_field, rows)
    end
    return total
end

function _auto_report_row_field(section, section_name::Symbol)
    row_fields = _report_row_fields(section)
    isempty(row_fields) &&
        throw(ArgumentError("fit report section $(String(section_name)) does not contain row fields"))
    :rows in row_fields && return :rows
    :diagnostic_rows in row_fields && return :diagnostic_rows
    return first(row_fields)
end

"""
    fit_report_sections(report)

Return a compact summary of the tabular/status-bearing sections in a
`fit_report` payload. `report` may be the original `NamedTuple` returned by
[`fit_report`](@ref) or the `Dict{String,Any}` payload returned by
[`load_fit_report`](@ref).

Each returned row includes `section`, `status`, `row_fields`, and `n_rows`.
JSON-loaded status strings are normalized to symbols.
"""
function fit_report_sections(report)
    _check_fit_report_payload(report)
    summaries = NamedTuple[]
    for section_name in _FIT_REPORT_SECTION_ORDER
        section = _report_lookup(report, section_name, _FIT_REPORT_LOOKUP_MISSING)
        section === _FIT_REPORT_LOOKUP_MISSING && continue
        row_fields = _report_row_fields(section)
        push!(summaries, (;
            section = section_name,
            status = _report_status(section),
            row_fields,
            n_rows = _report_total_row_count(section, row_fields),
        ))
    end
    return summaries
end

const _FIT_REPORT_HEALTH_SCHEMA = "bayesianmgmfrm.fit_report_health.v1"

function _fit_report_health_error_row(section_name::Symbol, section)
    return (;
        section = section_name,
        exception = _report_symbol_value(
            _report_lookup(section, :exception, missing)),
        message = _report_lookup(section, :message, missing),
    )
end

function _derive_fit_report_health(report)
    n_sections = 0
    n_computed_sections = 0
    n_not_requested_sections = 0
    n_unsupported_sections = 0
    n_unclassified_sections = 0
    error_sections = NamedTuple[]
    for section_name in _FIT_REPORT_SECTION_ORDER
        section = _report_lookup(report, section_name,
            _FIT_REPORT_LOOKUP_MISSING)
        section === _FIT_REPORT_LOOKUP_MISSING && continue
        n_sections += 1
        status = _report_status(section)
        if status === :computed
            n_computed_sections += 1
        elseif status === :not_requested
            n_not_requested_sections += 1
        elseif status === :unsupported
            n_unsupported_sections += 1
        elseif status === :error
            push!(error_sections,
                _fit_report_health_error_row(section_name, section))
        else
            n_unclassified_sections += 1
        end
    end
    n_error_sections = length(error_sections)
    complete = n_error_sections == 0
    return (;
        schema = _FIT_REPORT_HEALTH_SCHEMA,
        object = :fit_report_health,
        status = complete ? :complete : :incomplete,
        complete,
        n_sections,
        n_computed_sections,
        n_not_requested_sections,
        n_unsupported_sections,
        n_error_sections,
        n_unclassified_sections,
        error_sections = Tuple(error_sections),
    )
end

function _fit_report_health_error_signatures(rows)
    (rows isa Tuple || rows isa AbstractVector) ||
        throw(ArgumentError("fit report health error_sections must be a tuple or vector"))
    return Tuple((;
        section = _report_symbol_value(_report_lookup(row, :section, missing)),
        exception = _report_symbol_value(_report_lookup(row, :exception, missing)),
        message = _report_lookup(row, :message, missing),
    ) for row in rows)
end

function _check_recorded_fit_report_health(report, derived)
    recorded_status = _report_lookup(report, :report_status,
        _FIT_REPORT_LOOKUP_MISSING)
    if recorded_status !== _FIT_REPORT_LOOKUP_MISSING
        _report_symbol_value(recorded_status) === derived.status ||
            throw(ArgumentError(
                "fit report report_status is inconsistent with its sections"))
    end
    recorded = _report_lookup(report, :report_health,
        _FIT_REPORT_LOOKUP_MISSING)
    recorded === _FIT_REPORT_LOOKUP_MISSING && return derived
    schema = _report_lookup(recorded, :schema, _FIT_REPORT_LOOKUP_MISSING)
    schema === _FIT_REPORT_LOOKUP_MISSING || schema == _FIT_REPORT_HEALTH_SCHEMA ||
        throw(ArgumentError("fit report health has an unsupported schema"))
    object = _report_lookup(recorded, :object, _FIT_REPORT_LOOKUP_MISSING)
    object === _FIT_REPORT_LOOKUP_MISSING ||
        _report_symbol_value(object) === :fit_report_health ||
        throw(ArgumentError("fit report health has an unsupported object"))
    for field in (
            :status,
            :complete,
            :n_sections,
            :n_computed_sections,
            :n_not_requested_sections,
            :n_unsupported_sections,
            :n_error_sections,
            :n_unclassified_sections,
        )
        recorded_value = _report_lookup(recorded, field,
            _FIT_REPORT_LOOKUP_MISSING)
        recorded_value === _FIT_REPORT_LOOKUP_MISSING &&
            throw(ArgumentError("fit report health is missing field $field"))
        expected = getproperty(derived, field)
        normalized = field === :status ?
            _report_symbol_value(recorded_value) : recorded_value
        isequal(normalized, expected) || throw(ArgumentError(
            "fit report health field $field is inconsistent with its sections"))
    end
    recorded_errors = _report_lookup(recorded, :error_sections,
        _FIT_REPORT_LOOKUP_MISSING)
    recorded_errors === _FIT_REPORT_LOOKUP_MISSING &&
        throw(ArgumentError("fit report health is missing error_sections"))
    _fit_report_health_error_signatures(recorded_errors) ==
        _fit_report_health_error_signatures(derived.error_sections) ||
        throw(ArgumentError(
            "fit report health error_sections are inconsistent with its sections"))
    return derived
end

"""
    fit_report_health(report)

Derive the completeness of a full or public fit report from its section
statuses. A report is `:incomplete` when at least one section has
`status = :error`; `:not_requested`, `:unsupported`, and status-bearing
diagnostic sections do not by themselves make it incomplete. New reports store
the same result in `report_status` and `report_health`; recorded values are
validated against the sections. Legacy v1 reports without these fields remain
readable because their health is derived on demand.
"""
function fit_report_health(report)
    _check_fit_report_payload(report)
    return _check_recorded_fit_report_health(
        report,
        _derive_fit_report_health(report),
    )
end

function _require_complete_fit_report(report, caller::Symbol)
    health = fit_report_health(report)
    health.complete && return health
    failed = Tuple(row.section for row in health.error_sections)
    throw(ArgumentError(
        "$(String(caller)) requires a complete fit report; " *
        "error_sections=$(repr(failed))",
    ))
end

"""
    fit_report_section(report, section)

Return one section from a `fit_report` payload. `section` may be a `Symbol` or
string, and `report` may be either the in-memory report `NamedTuple` or a
JSON-loaded `Dict{String,Any}`.
"""
function fit_report_section(report, section)
    _check_fit_report_payload(report)
    section_name = _report_key_symbol(section)
    value = _report_lookup(report, section_name, _FIT_REPORT_LOOKUP_MISSING)
    value === _FIT_REPORT_LOOKUP_MISSING &&
        throw(ArgumentError("fit report section $(String(section_name)) was not found"))
    return value
end

"""
    fit_report_rows(report, section; row_field = :auto)

Return rows from one `fit_report` section. By default, `:auto` selects `:rows`
when present and otherwise selects `:diagnostic_rows`; pass `row_field` to
request a specific row field such as `:parameter_rows` from the diagnostics
section.
"""
function fit_report_rows(report, section; row_field = :auto)
    section_name = _report_key_symbol(section)
    section_value = fit_report_section(report, section_name)
    requested = _report_key_symbol(row_field)
    resolved = requested == :auto ?
        _auto_report_row_field(section_value, section_name) : requested
    rows = _report_lookup(section_value, resolved, _FIT_REPORT_LOOKUP_MISSING)
    rows isa AbstractVector ||
        throw(ArgumentError("fit report section $(String(section_name)) does not contain row field $(String(resolved))"))
    return rows
end

function _report_symbol_value(value)
    value isa Symbol && return value
    value isa AbstractString && return Symbol(value)
    return value
end

function _fit_report_file_component(name::Symbol)
    component = replace(String(name), r"[^A-Za-z0-9_]+" => "_")
    return isempty(component) ? "field" : component
end

function _fit_report_table_filename(section::Symbol, row_field::Symbol)
    return string(_fit_report_file_component(section), "__",
        _fit_report_file_component(row_field), ".json")
end

function _fit_report_table_hash_record(payload; scope::Symbol)
    hash_payload = _json_hash_value(_artifact_hash_payload(_json_export_value(payload)))
    canonical = _cache_stable_string(hash_payload)
    return (;
        algorithm = :sha256,
        value = bytes2hex(sha256(IOBuffer(canonical))),
        scope,
        canonicalization = :cache_stable_string,
        n_canonical_bytes = sizeof(canonical),
    )
end

function _fit_report_table_record(report, section_name::Symbol, row_field::Symbol)
    rows = fit_report_rows(report, section_name; row_field)
    payload = (;
        schema = "bayesianmgmfrm.fit_report_table.v1",
        object = :fit_report_table,
        section = section_name,
        row_field,
        n_rows = length(rows),
        rows,
    )
    return merge(payload, (;
        content_hash = _fit_report_table_hash_record(payload;
            scope = :fit_report_table_without_hash_metadata),
    ))
end

function _fit_report_table_records(report)
    _check_fit_report_payload(report)
    records = NamedTuple[]
    for section in fit_report_sections(report)
        for row_field in section.row_fields
            push!(records, _fit_report_table_record(report, section.section, row_field))
        end
    end
    return records
end

function _fit_report_table_manifest(report, table_records;
        label = nothing,
        source_path = nothing)
    table_rows = NamedTuple[]
    total_rows = 0
    for record in table_records
        total_rows += record.n_rows
        push!(table_rows, (;
            section = record.section,
            row_field = record.row_field,
            filename = _fit_report_table_filename(record.section, record.row_field),
            n_rows = record.n_rows,
            content_hash = record.content_hash,
        ))
    end
    location = source_path === nothing ? NamedTuple() : (;
        source_path = String(source_path),
    )
    payload = merge((;
        schema = "bayesianmgmfrm.fit_report_table_export.v1",
        object = :fit_report_table_export,
        created_at = string(now()),
        label = label === nothing ? missing : label,
    ), location, (;
        report_schema = _report_lookup(report, :schema, missing),
        report_object = _report_symbol_value(_report_lookup(report, :object, missing)),
        report_content_hash = _fit_report_content_hash_record(report),
        table_format = :json,
        manifest_filename = "manifest.json",
        n_tables = length(table_rows),
        n_rows = total_rows,
        tables = table_rows,
    ))
    return merge(payload, (;
        content_hash = _fit_report_table_hash_record(payload;
            scope = :fit_report_table_export_without_hash_metadata),
    ))
end

function _check_fit_report_table_export_directory(directory::AbstractString,
        table_records;
        overwrite::Bool)
    if ispath(directory) && !isdir(directory)
        throw(ArgumentError("fit report table export path exists and is not a directory: $directory"))
    end
    if isdir(directory) && !overwrite && !isempty(readdir(directory))
        throw(ArgumentError("fit report table export directory is not empty at $directory; pass overwrite = true to replace export files"))
    end
    seen = Set{String}()
    for record in table_records
        filename = _fit_report_table_filename(record.section, record.row_field)
        filename in seen &&
            throw(ArgumentError("fit report table export filename collision for $filename"))
        push!(seen, filename)
    end
    return true
end

function _write_json_record(path::AbstractString, record)
    open(path, "w") do io
        JSON3.write(io, _json_export_value(record))
        write(io, "\n")
    end
    return path
end

"""
    save_fit_report_tables(directory, report; overwrite = false, label = nothing,
        require_complete = false)
    save_fit_report_tables(directory, fit; overwrite = false, label = nothing,
        require_complete = false, kwargs...)

Write every tabular row field from a `fit_report` payload into a directory of
portable JSON table files plus `manifest.json`. The returned manifest records
the exported table filenames, row counts, and table content hashes. `report` may
be an in-memory `fit_report` `NamedTuple` or a JSON-loaded report payload from
[`load_fit_report`](@ref). Passing a fit object first builds
`fit_report(fit; kwargs...)`. Set `require_complete = true` to reject captured
section errors before creating the export directory.
"""
function save_fit_report_tables(directory::AbstractString,
        report;
        overwrite::Bool = false,
        label = nothing,
        require_complete::Bool = false)
    _check_fit_report_payload(report)
    require_complete &&
        _require_complete_fit_report(report, :save_fit_report_tables)
    table_records = _fit_report_table_records(report)
    _check_fit_report_table_export_directory(directory, table_records;
        overwrite)
    mkpath(directory)
    for record in table_records
        path = joinpath(directory,
            _fit_report_table_filename(record.section, record.row_field))
        _write_json_record(path, record)
    end
    manifest = _fit_report_table_manifest(report, table_records;
        label,
        source_path = _is_public_fit_report(report) ? nothing : directory)
    _write_json_record(joinpath(directory, "manifest.json"), manifest)
    return manifest
end

function save_fit_report_tables(directory::AbstractString,
        fit::_ModelComparisonFit;
        overwrite::Bool = false,
        label = nothing,
        require_complete::Bool = false,
        kwargs...)
    report = fit_report(fit; require_complete, kwargs...)
    return save_fit_report_tables(directory, report;
        overwrite,
        label,
        require_complete)
end
