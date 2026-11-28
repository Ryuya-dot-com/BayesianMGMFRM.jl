function _domain_compilation_layout(design::FacetDesign)
    _is_mfrm_fixed_q(design.spec) && return _mfrm_fixed_q_parameter_layout(design)
    if design.spec.family === :mfrm &&
            design.spec.estimation_status === :specified_only
        return _specified_only_preview_parameter_layout(design)
    end
    return fit_ready_parameter_layout(design)
end

_domain_nt_get(row::NamedTuple, key::Symbol, default) =
    haskey(row, key) ? getproperty(row, key) : default

function _domain_constraint_row(design::FacetDesign, block)
    ismissing(block) && return nothing
    for row in constraint_table(design)
        row.block === block && return row
    end
    return nothing
end

function _domain_prior_row(spec::FacetSpec, block)
    ismissing(block) && return nothing
    for row in spec.prior_blocks
        row.block === block && return row
    end
    return nothing
end

function _domain_transform_row(layout, block)
    ismissing(block) && return nothing
    for row in layout.transforms
        row.constrained_block === block && return row
    end
    return nothing
end

function _domain_block_row(rows, block)
    ismissing(block) && return nothing
    for row in rows
        row.block === block && return row
    end
    return nothing
end

function _domain_option_value(spec::FacetSpec, option::Symbol)
    option === :family && return spec.family
    option === :thresholds && return spec.thresholds
    option === :dimensions && return spec.dimensions
    option === :discrimination && return spec.discrimination
    option === :q_matrix && return _q_matrix_manifest(spec.q_matrix)
    option === :bias && return copy(spec.validation_bias_terms)
    option === :anchors && return copy(spec.anchors)
    option === :validation && return spec.validation.options_signature
    return missing
end

function _domain_option_for_block(spec::FacetSpec, block::Symbol)
    block === :person && return :dimensions
    block in (:rater, :rater_free, :item) && return :family
    block in (:thresholds, :rater_steps, :item_steps) && return :thresholds
    block in (:discrimination, :item_discrimination, :rater_consistency) &&
        return :discrimination
    block === :item_dimension_discrimination && return :q_matrix
    return :family
end

function _domain_role_for_block(block::Symbol)
    block in (:person, :rater, :rater_free, :item) && return :additive_block
    block in (:thresholds, :rater_steps, :item_steps) && return :scoring_block
    block === :item_dimension_discrimination && return :loading_block
    block in (:discrimination, :item_discrimination, :rater_consistency) &&
        return :discrimination_block
    return :parameter_block
end

function _domain_scoring_block(spec::FacetSpec)
    _is_mfrm_fixed_q(spec) && return :item_steps
    spec.family === :gmfrm && return :rater_steps
    spec.family === :mgmfrm && return :item_steps
    return :thresholds
end

function _domain_row(spec::FacetSpec,
        layout;
        domain_option::Symbol,
        option_value = _domain_option_value(spec, domain_option),
        compiled_role::Symbol,
        block = missing,
        raw_block = missing,
        constrained_block = block,
        parameter_names = String[],
        raw_parameter_names = String[],
        constraint = missing,
        transform = missing,
        prior_block = missing,
        prior = missing,
        scoring_vector = Int[],
        loading_mask = nothing,
        validation_requirement = missing,
        status = layout.status,
        note = "")
    return (;
        family = spec.family,
        scope = layout.scope,
        estimation_status = spec.estimation_status,
        compiler_stage = layout.compiler_stage,
        density_space = layout.density_space,
        parameterization = layout.parameterization,
        fit_ready = layout.fit_ready,
        public_fit = layout.public_fit,
        experimental_public = layout.experimental_public,
        domain_option,
        option_value,
        compiled_role,
        block,
        raw_block,
        constrained_block,
        parameter_names = copy(parameter_names),
        raw_parameter_names = copy(raw_parameter_names),
        constraint,
        transform,
        prior_block,
        prior,
        scoring_vector = copy(scoring_vector),
        loading_mask,
        validation_requirement,
        status,
        note,
    )
end

function _domain_block_summary_row(spec::FacetSpec,
        design::FacetDesign,
        layout,
        block::Symbol)
    constrained = _domain_block_row(layout.constrained_blocks, block)
    transform = _domain_transform_row(layout, block)
    constraint = _domain_constraint_row(design, block)
    prior = _domain_prior_row(spec, block)
    domain_option = _domain_option_for_block(spec, block)
    parameter_names = constrained === nothing ? String[] : constrained.parameter_names
    raw_block = transform === nothing ? block : transform.raw_block
    raw_names = transform === nothing ? String[] : transform.raw_parameter_names
    return _domain_row(spec, layout;
        domain_option,
        compiled_role = _domain_role_for_block(block),
        block,
        raw_block,
        constrained_block = block,
        parameter_names,
        raw_parameter_names = raw_names,
        constraint = constraint === nothing ? missing : constraint.constraint,
        transform = transform === nothing ? missing : transform.transform,
        prior_block = transform === nothing ?
            (prior === nothing ? missing : prior.block) :
            _domain_nt_get(transform, :prior_block,
                prior === nothing ? missing : prior.block),
        prior = prior === nothing ? missing : prior.prior,
        validation_requirement = :parameter_block_compiled,
        status = constraint === nothing ? layout.status : constraint.status,
        note = constraint === nothing ? "" : constraint.note,
    )
end

function _domain_validation_requirement_rows(spec::FacetSpec, layout)
    rows = NamedTuple[]
    summary = _validation_summary(spec.validation)
    push!(rows, _domain_row(spec, layout;
        domain_option = :validation,
        option_value = summary,
        compiled_role = :validation_requirement,
        validation_requirement = :validated_facet_design,
        status = spec.validation.passed ? :passed : :failed,
        note = "validation report attached to the compiled specification",
    ))
    for term in spec.validation_bias_terms
        block = Symbol("dff_", term[1], "_", term[2])
        push!(rows, _domain_row(spec, layout;
            domain_option = :bias,
            option_value = term,
            compiled_role = :validation_requirement,
            block,
            constrained_block = block,
            constraint = :validation_only,
            transform = :none,
            validation_requirement = :dff_cell_counts,
            status = :validation_only,
            note = "DFF/bias term validated for sparse cells but not included in the fitted likelihood",
        ))
    end
    for anchor in spec.anchors
        anchor_type = haskey(anchor, :anchor_type) ? anchor.anchor_type : _normalize_anchor_type(anchor)
        anchor_scale = haskey(anchor, :anchor_scale) ? anchor.anchor_scale : _anchor_scale(anchor)
        push!(rows, _domain_row(spec, layout;
            domain_option = :anchors,
            option_value = anchor,
            compiled_role = :constraint,
            block = anchor.block,
            constrained_block = anchor.block,
            constraint = anchor_type,
            transform = anchor_type === :soft_anchor ? :soft_anchor_prior : :fixed_value,
            validation_requirement = :anchor_declared,
            status = spec.estimation_status === :fit_supported &&
                anchor_type === :hard_anchor ? :implemented : :specified_only,
            note = anchor_type === :soft_anchor ?
                "soft anchor declared with scale $(anchor_scale)" :
                spec.estimation_status === :fit_supported ?
                    "hard anchor compiled as an exact fixed coordinate" :
                    "hard anchor declared with fixed value",
        ))
    end
    return rows
end

function _public_domain_option_value(row)
    if row.domain_option === :anchors && row.option_value isa NamedTuple
        return _public_anchor_manifest(row.option_value)
    elseif row.option_value isa AbstractArray
        return copy(row.option_value)
    end
    return row.option_value
end

function _public_domain_compilation_row(row, spec::FacetSpec)
    availability = _public_model_availability(spec)
    return (;
        schema = "bayesianmgmfrm.domain_compilation_row_public.v1",
        family = row.family,
        stability = availability.stability,
        fit_available = availability.fit_available,
        entrypoint = availability.entrypoint,
        claim_scope = availability.claim_scope,
        domain_option = row.domain_option,
        option_value = _public_domain_option_value(row),
        compiled_role = row.compiled_role,
        block = row.block,
        raw_block = row.raw_block,
        constrained_block = row.constrained_block,
        parameter_names = copy(row.parameter_names),
        raw_parameter_names = copy(row.raw_parameter_names),
        constraint = row.constraint,
        transform = row.transform,
        prior_block = row.prior_block,
        prior = row.prior,
        scoring_vector = copy(row.scoring_vector),
        loading_mask = row.loading_mask isa AbstractArray ?
            copy(row.loading_mask) : row.loading_mask,
        validation_requirement = row.validation_requirement,
        note = row.note,
    )
end

"""
    domain_compilation_summary(spec_or_design; preview = false, view = :full)

Return a review table showing how domain options were compiled into the current
design contract. Rows cover likelihood family, additive/location blocks,
discrimination or loading blocks, scoring vectors, constraints, priors, fixed
Q-masks, validation requirements, DFF/bias validation terms, and anchors.

Fit-supported MFRM/RSM/PCM designs report `fit_ready = true` and
`public_fit = true`. Specified-only GMFRM/MGMFRM previews report the
parameterization without enabling broad generalized fitting. For
specified-only `FacetSpec` values, pass `preview = true`, matching
[`getdesign`](@ref). The compatibility default `view = :full` retains the
complete compiler record. Use `view = :public` for rows that state stable or
fit availability directly, omit compiler-control fields, and
redact non-scientific anchor metadata.
"""
function domain_compilation_summary(spec::FacetSpec;
        preview::Bool = false,
        view::Symbol = :full)
    view in (:full, :public) ||
        throw(ArgumentError("view must be :full or :public"))
    return domain_compilation_summary(getdesign(spec; preview); view)
end

function domain_compilation_summary(design::FacetDesign;
        preview::Bool = false,
        view::Symbol = :full)
    view in (:full, :public) ||
        throw(ArgumentError("view must be :full or :public"))
    preview &&
        throw(ArgumentError("preview is only a FacetSpec compilation option; pass domain_compilation_summary(spec; preview = true)"))
    spec = design.spec
    layout = _domain_compilation_layout(design)
    rows = NamedTuple[]
    push!(rows, _domain_row(spec, layout;
        domain_option = :family,
        compiled_role = :likelihood_kernel,
        validation_requirement = :likelihood_family_checked,
        status = layout.status,
        note = model_equation(spec).kernel,
    ))
    for block_row in layout.constrained_blocks
        push!(rows, _domain_block_summary_row(spec, design, layout, block_row.block))
    end
    scoring_block = _domain_scoring_block(spec)
    scoring_constraint = _domain_constraint_row(design, scoring_block)
    scoring_transform = _domain_transform_row(layout, scoring_block)
    scoring_names = begin
        row = _domain_block_row(layout.constrained_blocks, scoring_block)
        row === nothing ? String[] : row.parameter_names
    end
    push!(rows, _domain_row(spec, layout;
        domain_option = :thresholds,
        compiled_role = :scoring_vector,
        block = scoring_block,
        raw_block = scoring_transform === nothing ? scoring_block : scoring_transform.raw_block,
        constrained_block = scoring_block,
        parameter_names = scoring_names,
        raw_parameter_names = scoring_transform === nothing ? String[] :
            scoring_transform.raw_parameter_names,
        constraint = scoring_constraint === nothing ? missing : scoring_constraint.constraint,
        transform = scoring_constraint === nothing ? missing : scoring_constraint.transform,
        prior_block = scoring_transform === nothing ? scoring_block :
            _domain_nt_get(scoring_transform, :prior_block, scoring_block),
        prior = begin
            prior = _domain_prior_row(spec, scoring_block)
            prior === nothing ? missing : prior.prior
        end,
        scoring_vector = spec.data.category_levels,
        validation_requirement = :ordinal_score_categories,
        status = scoring_constraint === nothing ? layout.status : scoring_constraint.status,
        note = "observed ordinal categories used by row-by-category predictors",
    ))
    if spec.q_matrix !== nothing
        q_block = _is_mfrm_fixed_q(spec) ? :q_matrix : :item_dimension_discrimination
        q_transform = _domain_transform_row(layout, q_block)
        q_constraint = _domain_constraint_row(design, q_block)
        q_names = begin
            row = _domain_block_row(layout.constrained_blocks, q_block)
            row === nothing ? String[] : row.parameter_names
        end
        push!(rows, _domain_row(spec, layout;
            domain_option = :q_matrix,
            compiled_role = :loading_mask,
            block = q_block,
            raw_block = q_transform === nothing ? q_block : q_transform.raw_block,
            constrained_block = q_block,
            parameter_names = q_names,
            raw_parameter_names = q_transform === nothing ? String[] :
                q_transform.raw_parameter_names,
            constraint = q_constraint === nothing ? :fixed_mask : q_constraint.constraint,
            transform = q_transform === nothing ? :fixed_mask : q_transform.transform,
            prior_block = q_transform === nothing ? missing :
                _domain_nt_get(q_transform, :prior_block, missing),
            prior = begin
                prior = _domain_prior_row(spec, q_block)
                prior === nothing ? missing : prior.prior
            end,
            loading_mask = _q_matrix_manifest(spec.q_matrix),
            validation_requirement = :fixed_q_matrix_validated,
            status = q_constraint === nothing ? layout.status : q_constraint.status,
            note = "fixed confirmatory item-by-dimension loading mask",
        ))
    end
    append!(rows, _domain_validation_requirement_rows(spec, layout))
    return view === :public ?
        [_public_domain_compilation_row(row, spec) for row in rows] : rows
end

function _surface_status_policy_for_spec(spec::FacetSpec)
    return _status_policy_manifest(
        spec.family,
        spec.estimation_status;
        public_fit = spec.estimation_status === :fit_supported,
        experimental_public = false,
        fit_ready = spec.estimation_status === :fit_supported,
        claim_scope = _spec_scope(spec),
    )
end

function _surface_source_symbol(family::Symbol, block; dimensions::Int = 1)
    ismissing(block) && return missing
    _is_mfrm_fixed_q(family, dimensions) && block === :person && return "theta_pd"
    family === :mfrm && block === :rater_free && return "beta_r (last reconstructed)"
    family === :mfrm && block === :item_steps && return "d_im"
    family === :mfrm && block === :person && return "theta_p"
    family === :mfrm && block === :rater && return "beta_r"
    family === :mfrm && block === :item && return "beta_i"
    family === :mfrm && block === :thresholds && return "d_m or d_im"
    family === :gmfrm && block === :person && return "theta_j"
    family === :gmfrm && block === :rater && return "beta_r"
    family === :gmfrm && block === :item && return "beta_i"
    family === :gmfrm && block === :item_discrimination && return "alpha_i"
    family === :gmfrm && block === :rater_consistency && return "alpha_r"
    family === :gmfrm && block === :rater_steps && return "d_rm"
    family === :mgmfrm && block === :person && return "theta_jl"
    family === :mgmfrm && block === :rater && return "beta_r"
    family === :mgmfrm && block === :item && return "beta_i"
    family === :mgmfrm && block === :item_dimension_discrimination && return "alpha_il"
    family === :mgmfrm && block === :rater_consistency && return "alpha_r"
    family === :mgmfrm && block === :item_steps && return "d_im"
    family === :mgmfrm && block === :q_matrix && return "Q_il"
    startswith(String(block), "dff_") && return "validation cell"
    return String(block)
end

function _surface_direct_interpretation(family::Symbol, block)
    ismissing(block) && return missing
    family === :mfrm && block === :q_matrix && return "fixed item-by-dimension coefficients (zero or one)"
    block === :person && return family === :mgmfrm ?
        "person ability/location by dimension" :
        "person ability/location"
    block === :rater && return "rater severity"
    block === :rater_free && return "free rater severity; last rater reconstructed by a sum-to-zero constraint"
    block === :item && return "item/task difficulty"
    block === :thresholds && return "ordinal category threshold or step"
    block === :item_discrimination && return "positive item/task discrimination"
    block === :rater_consistency && return "positive rater consistency multiplier"
    block === :rater_steps && return "rater-specific category-use step"
    block === :item_dimension_discrimination &&
        return "positive fixed-Q item-by-dimension loading/discrimination"
    block === :item_steps && return "item-specific category-use step"
    block === :q_matrix && return "fixed confirmatory item-by-dimension mask"
    startswith(String(block), "dff_") &&
        return "DFF/bias validation cell, not a fitted model effect"
    return "model block"
end

function _surface_report_label(block)
    ismissing(block) && return missing
    block === :person && return :person_measure
    block === :rater && return :rater_severity
    block === :item && return :item_difficulty
    block === :thresholds && return :category_threshold
    block === :item_discrimination && return :item_discrimination
    block === :rater_consistency && return :rater_consistency
    block === :rater_steps && return :rater_category_step
    block === :item_dimension_discrimination && return :dimension_loading
    block === :item_steps && return :item_category_step
    block === :q_matrix && return :q_matrix
    startswith(String(block), "dff_") && return :dff_screening
    return block
end

function _surface_prior_scale(prior_block, block)
    ismissing(prior_block) && ismissing(block) && return missing
    prior_key = ismissing(prior_block) ? block : prior_block
    prior_key === :person && return :person_sd
    prior_key in (:rater, :rater_free) && return :rater_sd
    prior_key === :item && return :item_sd
    prior_key in (:thresholds, :rater_steps, :item_steps) && return :step_sd
    prior_key in (:item_discrimination, :log_item_discrimination,
        :log_item_dimension_discrimination) && return :log_discrimination_sd
    prior_key in (:rater_consistency, :log_rater_consistency) &&
        return :log_consistency_sd
    return missing
end

function _surface_prior_parameters(spec::FacetSpec, block, prior_block)
    if !ismissing(block)
        prior_row = _domain_prior_row(spec, block)
        prior_row === nothing || return prior_row.parameters
    end
    prior_scale = _surface_prior_scale(prior_block, block)
    ismissing(prior_scale) && return missing
    return (location = 0.0, scale = prior_scale)
end

function _model_surface_audit(design::FacetDesign; status_policy = _surface_status_policy_for_spec(design.spec))
    spec = design.spec
    rows = NamedTuple[]
    for row in domain_compilation_summary(design)
        haskey(row, :block) || continue
        block = row.block
        ismissing(block) && continue
        prior_scale = _surface_prior_scale(row.prior_block, block)
        push!(rows, (;
            schema = "bayesianmgmfrm.model_surface_audit_row.v1",
            family = spec.family,
            scope = status_policy.claim_scope,
            estimation_status = spec.estimation_status,
            current_status = status_policy.status_label,
            public_fit = status_policy.public_fit,
            experimental_public = status_policy.experimental_public,
            fit_ready = status_policy.fit_ready,
            stable_public = status_policy.stable_public,
            external_validated = status_policy.external_validated,
            block,
            compiled_role = row.compiled_role,
            source_symbol = _surface_source_symbol(spec.family, block; dimensions = spec.dimensions),
            direct_interpretation = _surface_direct_interpretation(spec.family, block),
            raw_coordinate = row.raw_block,
            constrained_block = row.constrained_block,
            constraint = row.constraint,
            transform = row.transform,
            prior_block = row.prior_block,
            prior = row.prior,
            prior_scale,
            prior_parameters = _surface_prior_parameters(spec, block, row.prior_block),
            report_label = _surface_report_label(block),
            parameter_names = copy(row.parameter_names),
            raw_parameter_names = copy(row.raw_parameter_names),
            block_status = row.status,
            blocked_claims = status_policy.blocked_claims,
            next_gate = status_policy.next_gate,
            note = row.note,
        ))
    end
    return rows
end

"""
    model_surface_audit(spec_or_design; preview = nothing, view = :full)

Return a machine-readable audit table for the current model surface. Rows trace
each parameter or validation block from the source-equation symbol to the direct
interpretation, raw coordinate, constraint, prior scale, report label, and
current status policy.

The compatibility default `view = :full` retains additional provenance fields.
Use `view = :public` for a concise reader-facing result. Public rows keep model
execution availability (`execution_status`, `fit_available`, and
`fit_entrypoint`) separate from each block's `declaration_status`.

For specified-only GMFRM/MGMFRM specs, `preview` defaults to `true` so the audit
can inspect the represented source-aligned blocks without enabling broad public
fitting. Passing a compiled `FacetDesign` audits that design directly.
"""
function model_surface_audit(spec::FacetSpec;
        preview::Union{Nothing,Bool} = nothing,
        view::Symbol = :full)
    view in (:full, :public) ||
        throw(ArgumentError("view must be :full or :public"))
    compile_preview = preview === nothing ?
        spec.estimation_status !== :fit_supported :
        preview
    design = getdesign(spec; preview = compile_preview)
    rows = _model_surface_audit(
        design;
        status_policy = _surface_status_policy_for_spec(spec),
    )
    return view === :public ?
        _public_model_surface_rows(rows, _public_model_availability(spec)) : rows
end

function model_surface_audit(design::FacetDesign;
        preview::Bool = false,
        view::Symbol = :full)
    view in (:full, :public) ||
        throw(ArgumentError("view must be :full or :public"))
    preview &&
        throw(ArgumentError("preview is only a FacetSpec compilation option; pass model_surface_audit(spec; preview = true)"))
    rows = _model_surface_audit(
        design;
        status_policy = _surface_status_policy_for_spec(design.spec),
    )
    return view === :public ? _public_model_surface_rows(
        rows,
        _public_model_availability(design.spec),
    ) : rows
end

function _model_surface_check_rows(rows)
    return [merge(row, (;
        schema = "bayesianmgmfrm.model_surface_check_row.v1",
    )) for row in rows]
end

"""
    model_surface_check(spec_or_design; preview = nothing, view = :full)

Check how each declared model block maps to parameters, constraints, priors,
report labels, and execution availability. Use `view = :public` for the
reader-facing projection.
"""
function model_surface_check(spec::FacetSpec;
        preview::Union{Nothing,Bool} = nothing,
        view::Symbol = :full)
    rows = model_surface_audit(spec; preview, view)
    return view === :full ? _model_surface_check_rows(rows) : rows
end

function model_surface_check(design::FacetDesign;
        preview::Bool = false,
        view::Symbol = :full)
    rows = model_surface_audit(design; preview, view)
    return view === :full ? _model_surface_check_rows(rows) : rows
end
