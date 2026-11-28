"""
    design_row_table(spec_or_design; preview = false)

Return one row of machine-readable design metadata per observed rating. The
table records the facet level indexes and labels, identified parameter indexes
and names touched by the row, the source-step path up to the observed category,
and preview-only generalized blocks such as item discrimination,
item-dimension discrimination, and rater consistency when a specified-only
GMFRM/MGMFRM design is compiled with `preview = true`.

For a `FacetSpec`, specified-only GMFRM/MGMFRM configurations are rejected
unless `preview = true`, matching [`getdesign`](@ref). The returned table is a
compiler inspection aid; it does not make specified-only likelihoods fit-ready.
"""
function design_row_table(spec::FacetSpec; preview::Bool = false)
    return design_row_table(getdesign(spec; preview))
end

function design_row_table(design::FacetDesign; preview::Bool = false)
    preview &&
        throw(ArgumentError("preview is only a FacetSpec compilation option; pass design_row_table(spec; preview = true) for specified-only specs"))
    data = design.spec.data
    index_by_name = _parameter_index_map(design)
    rows = NamedTuple[]
    for row in 1:data.n
        components = _predictor_components(design, index_by_name, row, data.category[row])
        push!(rows, (;
            row,
            score = data.score[row],
            category_index = data.category[row],
            category = data.category_levels[data.category[row]],
            person_index = data.person[row],
            person = data.person_levels[data.person[row]],
            person_parameter_indices = components.person_parameter_indices,
            person_parameter_names = components.person_parameter_names,
            rater_index = data.rater[row],
            rater = data.rater_levels[data.rater[row]],
            rater_parameter_index = components.rater_parameter_index,
            rater_parameter_name = components.rater_parameter_name,
            rater_parameter_status = components.rater_parameter_status,
            rater_fixed_value = components.rater_fixed_value,
            item_index = data.item[row],
            item = data.item_levels[data.item[row]],
            item_parameter_index = components.item_parameter_index,
            item_parameter_name = components.item_parameter_name,
            item_parameter_status = components.item_parameter_status,
            item_fixed_value = components.item_fixed_value,
            item_discrimination_parameter_index = components.item_discrimination_parameter_index,
            item_discrimination_parameter_name = components.item_discrimination_parameter_name,
            threshold_path = components.step_path,
            threshold_parameter_indices = components.step_parameter_indices,
            threshold_parameter_names = components.step_parameter_names,
            threshold_statuses = components.step_statuses,
            threshold_blocks = components.step_blocks,
            loading_dimensions = _loading_dimensions(design.spec, data.item[row]),
            loading_parameter_indices = components.item_dimension_discrimination_parameter_indices,
            loading_parameter_names = components.item_dimension_discrimination_parameter_names,
            item_dimension_discrimination_parameter_indices = components.item_dimension_discrimination_parameter_indices,
            item_dimension_discrimination_parameter_names = components.item_dimension_discrimination_parameter_names,
            rater_consistency_parameter_index = components.rater_consistency_parameter_index,
            rater_consistency_parameter_name = components.rater_consistency_parameter_name,
            discrimination_parameter_indices = components.discrimination_parameter_indices,
            discrimination_parameter_names = components.discrimination_parameter_names,
        ))
    end
    return rows
end

function _namedtuple_from_pairs(pairs)
    isempty(pairs) && return NamedTuple{()}(())
    names = Tuple(first(pair) for pair in pairs)
    values = Tuple(last(pair) for pair in pairs)
    return NamedTuple{names}(values)
end

function _optional_levels_manifest(data::FacetData)
    pairs = Pair{Symbol,Any}[]
    for role in sort(collect(keys(data.optional_levels)); by = string)
        push!(pairs, role => copy(data.optional_levels[role]))
    end
    return _namedtuple_from_pairs(pairs)
end

function _optional_columns_manifest(data::FacetData)
    pairs = Pair{Symbol,Any}[]
    for role in sort(collect(keys(data.columns.optional)); by = string)
        push!(pairs, role => data.columns.optional[role])
    end
    return _namedtuple_from_pairs(pairs)
end

function _data_manifest(data::FacetData)
    return (;
        n_observations = data.n,
        n_persons = length(data.person_levels),
        n_raters = length(data.rater_levels),
        n_items = length(data.item_levels),
        n_categories = length(data.category_levels),
        category_scale = _category_scale_contract(data),
        columns = (;
            person = data.columns.person,
            rater = data.columns.rater,
            item = data.columns.item,
            score = data.columns.score,
            optional = _optional_columns_manifest(data),
            missing_policy = data.columns.missing_policy,
        ),
        levels = (;
            person = copy(data.person_levels),
            rater = copy(data.rater_levels),
            item = copy(data.item_levels),
            category = copy(data.category_levels),
            optional = _optional_levels_manifest(data),
        ),
        optional_facets = sort(collect(keys(data.optional)); by = string),
        data_signature = _data_signature(data),
    )
end

function _issue_count_rows(report::ValidationReport)
    codes = sort(unique(issue.code for issue in report.issues); by = string)
    return [(; code, count = count(issue -> issue.code === code, report.issues)) for code in codes]
end

function _validation_manifest(report::ValidationReport)
    return (;
        passed = report.passed,
        n_issues = length(report.issues),
        n_errors = count(issue -> issue.severity === :error, report.issues),
        n_warnings = count(issue -> issue.severity === :warning, report.issues),
        issue_counts = _issue_count_rows(report),
        issues = [(;
            code = issue.code,
            severity = issue.severity,
            message = issue.message,
            context = copy(issue.context),
        ) for issue in report.issues],
        suggestions = validation_suggestions(report),
        data_signature = report.data_signature,
        options_signature = report.options_signature,
    )
end

function _q_matrix_manifest(q_matrix::Union{Nothing,Matrix{Bool}})
    q_matrix === nothing && return nothing
    return [q_matrix[row, col] for row in axes(q_matrix, 1), col in axes(q_matrix, 2)]
end

function _spec_manifest(spec::FacetSpec)
    manifest = (;
        family = spec.family,
        scope = _spec_scope(spec),
        thresholds = spec.thresholds,
        dimensions = spec.dimensions,
        dimension_labels = copy(spec.dimension_labels),
        discrimination = spec.discrimination,
        q_matrix = _q_matrix_manifest(spec.q_matrix),
        q_matrix_validation = q_matrix_validation(spec),
        validation_bias_terms = copy(spec.validation_bias_terms),
        anchors = copy(spec.anchors),
        estimation_status = spec.estimation_status,
        status_policy = _status_policy_manifest(
            spec.family,
            spec.estimation_status;
            public_fit = spec.estimation_status === :fit_supported,
            experimental_public = false,
            fit_ready = spec.estimation_status === :fit_supported,
            claim_scope = _spec_scope(spec),
        ),
        required_facets = (:person, :rater, :item),
        optional_facets = sort(collect(keys(spec.data.optional)); by = string),
        equation = model_equation(spec),
        identification_declarations = identification_declarations(spec),
        constraints = constraint_table(spec),
        model_surface_audit = model_surface_audit(spec),
        prior_blocks = copy(spec.prior_blocks),
    )
    return _is_mfrm_fixed_q(spec) ? merge(manifest, _mfrm_fixed_q_spec_metadata()) : manifest
end

function _design_block_rows(design::FacetDesign)
    rows = NamedTuple[]
    for block in sort(collect(keys(design.blocks)); by = string)
        range = design.blocks[block]
        indices = collect(range)
        names = isempty(indices) ? String[] : design.parameter_names[indices]
        push!(rows, (;
            block,
            first_parameter = isempty(indices) ? missing : first(indices),
            last_parameter = isempty(indices) ? missing : last(indices),
            n_parameters = length(indices),
            parameter_names = copy(names),
            identification = design.identification[block],
        ))
    end
    return rows
end

function _stable_fixed_coordinate_rows(design::FacetDesign)
    design.spec.family === :mfrm &&
        design.spec.estimation_status === :fit_supported || return NamedTuple[]
    data = design.spec.data
    fixed_map = _stable_hard_anchor_map(design)
    rows = NamedTuple[]
    for block in (:rater, :item)
        levels = block === :rater ? data.rater_levels : data.item_levels
        if isempty(fixed_map[block])
            isempty(levels) || push!(rows, (;
                block,
                level_index = 1,
                level = levels[1],
                value = 0.0,
                status = :reference_zero,
                source = :default_identification,
                sampled = false,
            ))
        else
            for level_index in sort!(collect(keys(fixed_map[block])))
                push!(rows, (;
                    block,
                    level_index,
                    level = levels[level_index],
                    value = fixed_map[block][level_index],
                    status = :hard_anchor,
                    source = :declared_anchor,
                    sampled = false,
                ))
            end
        end
    end
    return rows
end

function _block_manifest_rows(blocks::Dict{Symbol,UnitRange{Int}}, parameter_names::Vector{String})
    rows = NamedTuple[]
    for block in sort(collect(keys(blocks)); by = string)
        range = blocks[block]
        indices = collect(range)
        push!(rows, (;
            block,
            first_parameter = isempty(indices) ? missing : first(indices),
            last_parameter = isempty(indices) ? missing : last(indices),
            n_parameters = length(indices),
            parameter_names = isempty(indices) ? String[] : copy(parameter_names[indices]),
        ))
    end
    return rows
end

function _direct_identity_transform_rows(design::FacetDesign)
    rows = NamedTuple[]
    for block in sort(collect(keys(design.blocks)); by = string)
        range = design.blocks[block]
        indices = collect(range)
        names = isempty(indices) ? String[] : copy(design.parameter_names[indices])
        push!(rows, (;
            raw_block = block,
            constrained_block = block,
            transform = :identity,
            constraint = design.identification[block],
            status = design.spec.estimation_status,
            raw_first_parameter = isempty(indices) ? missing : first(indices),
            raw_last_parameter = isempty(indices) ? missing : last(indices),
            raw_n_parameters = length(indices),
            raw_parameter_names = copy(names),
            constrained_first_parameter = isempty(indices) ? missing : first(indices),
            constrained_last_parameter = isempty(indices) ? missing : last(indices),
            constrained_n_parameters = length(indices),
            constrained_parameter_names = copy(names),
            jacobian_policy = :identity,
        ))
    end
    return rows
end

function _mfrm_fit_ready_parameter_layout(design::FacetDesign)
    design.spec.family === :mfrm &&
        design.spec.estimation_status === :fit_supported ||
        throw(ArgumentError("fit-ready MFRM parameter layout requires a fit-supported MFRM/RSM/PCM design"))
    block_rows = _block_manifest_rows(design.blocks, design.parameter_names)
    fixed_coordinates = _stable_fixed_coordinate_rows(design)
    return (;
        schema = "bayesianmgmfrm.fit_ready_parameter_layout.v1",
        family = :mfrm,
        scope = _spec_scope(design.spec),
        status = :fit_supported,
        compiler_stage = :fit_supported_design,
        likelihood = :mfrm_rsm_pcm,
        fit_ready = true,
        public_fit = true,
        experimental_public = false,
        density_space = :constrained_direct,
        parameterization = :direct,
        n_parameters = length(design.parameter_names),
        parameter_names = copy(design.parameter_names),
        blocks = block_rows,
        n_raw_parameters = length(design.parameter_names),
        raw_parameter_names = copy(design.parameter_names),
        raw_blocks = copy(block_rows),
        n_constrained_parameters = length(design.parameter_names),
        constrained_parameter_names = copy(design.parameter_names),
        constrained_blocks = copy(block_rows),
        n_fixed_coordinates = length(fixed_coordinates),
        fixed_coordinates,
        transforms = _direct_identity_transform_rows(design),
        constraints = constraint_table(design),
        identification_declarations = identification_declarations(design),
    )
end

function _generalized_fit_ready_parameter_layout(design::FacetDesign, blueprint)
    transforms = _source_transform_manifest_rows(blueprint)
    raw_blocks = _block_manifest_rows(blueprint.blocks, blueprint.parameter_names)
    constrained_blocks = _block_manifest_rows(
        blueprint.constrained_blocks,
        blueprint.constrained_parameter_names,
    )
    likelihood = design.spec.family === :gmfrm ?
        :scalar_gmfrm_source_aligned :
        :confirmatory_mgmfrm_source_aligned
    return (;
        schema = "bayesianmgmfrm.fit_ready_parameter_layout.v1",
        family = design.spec.family,
        scope = blueprint.scope,
        status = blueprint.status,
        compiler_stage = blueprint.compiler_stage,
        likelihood,
        fit_ready = blueprint.fit_ready,
        public_fit = false,
        experimental_public = design.spec.family in (:gmfrm, :mgmfrm),
        density_space = :raw_unconstrained,
        parameterization = :raw_to_constrained,
        n_parameters = blueprint.n_parameters,
        parameter_names = copy(blueprint.parameter_names),
        blocks = raw_blocks,
        n_raw_parameters = blueprint.n_parameters,
        raw_parameter_names = copy(blueprint.parameter_names),
        raw_blocks,
        n_constrained_parameters = length(blueprint.constrained_parameter_names),
        constrained_parameter_names = copy(blueprint.constrained_parameter_names),
        constrained_blocks,
        transforms,
        constraints = _fit_ready_candidate_constraint_rows(blueprint),
        identification_declarations = identification_declarations(design),
    )
end

const _PUBLIC_PARAMETER_LAYOUT_ROW_FIELDS = Set((
    :anchor_scale,
    :anchor_target,
    :anchor_type,
    :anchor_value,
    :block,
    :components,
    :constrained_block,
    :constrained_first_parameter,
    :constrained_last_parameter,
    :constrained_n_parameters,
    :constrained_parameter_names,
    :constraint,
    :dimensions,
    :family,
    :first_parameter,
    :fixed_value,
    :identification,
    :is_fixed,
    :jacobian_policy,
    :last_parameter,
    :level,
    :level_index,
    :n_parameters,
    :parameter_names,
    :prior_block,
    :raw_block,
    :raw_first_parameter,
    :raw_last_parameter,
    :raw_n_parameters,
    :raw_parameter_names,
    :rule,
    :sampled,
    :source,
    :status,
    :transform,
    :value,
))

function _public_parameter_layout_row(row::NamedTuple;
        include_status::Bool = false)
    pairs = Pair{Symbol,Any}[]
    for field in keys(row)
        field in _PUBLIC_PARAMETER_LAYOUT_ROW_FIELDS || continue
        field === :status && !include_status && continue
        value = getproperty(row, field)
        if value isa AbstractArray
            value = copy(value)
        end
        push!(pairs, field => value)
    end
    return (; pairs...)
end

function _public_fit_ready_parameter_layout(layout, spec::FacetSpec)
    availability = _public_model_availability(spec)
    return (;
        schema = "bayesianmgmfrm.fit_ready_parameter_layout_public.v1",
        object = :fit_ready_parameter_layout,
        family = layout.family,
        stability = availability.stability,
        fit_available = availability.fit_available,
        entrypoint = availability.entrypoint,
        claim_scope = availability.claim_scope,
        likelihood = layout.likelihood,
        density_space = layout.density_space,
        parameterization = layout.parameterization,
        n_parameters = layout.n_parameters,
        parameter_names = copy(layout.parameter_names),
        blocks = [_public_parameter_layout_row(row) for row in layout.blocks],
        n_raw_parameters = layout.n_raw_parameters,
        raw_parameter_names = copy(layout.raw_parameter_names),
        raw_blocks = [_public_parameter_layout_row(row) for row in layout.raw_blocks],
        n_constrained_parameters = layout.n_constrained_parameters,
        constrained_parameter_names = copy(layout.constrained_parameter_names),
        constrained_blocks = [
            _public_parameter_layout_row(row) for row in layout.constrained_blocks
        ],
        n_fixed_coordinates = _domain_nt_get(layout, :n_fixed_coordinates, 0),
        fixed_coordinates = [
            _public_parameter_layout_row(row; include_status = true)
            for row in _domain_nt_get(layout, :fixed_coordinates, NamedTuple[])
        ],
        transforms = [
            _public_parameter_layout_row(row) for row in layout.transforms
        ],
        constraints = [
            _public_parameter_layout_row(row) for row in layout.constraints
        ],
        identification_declarations = [
            _public_parameter_layout_row(row)
            for row in layout.identification_declarations
        ],
    )
end

"""
    fit_ready_parameter_layout(spec_or_design; preview = false, view = :full)

Return deterministic parameter names and block ranges for each compiled
likelihood layout currently represented by the package. The fit-supported
MFRM/RSM/PCM path reports direct parameter blocks. Specified-only GMFRM/MGMFRM
preview designs report raw and constrained fit-ready blocks,
including raw-to-constrained transform rows, without enabling broad public
generalized fitting.

For specified-only `FacetSpec` values, pass `preview = true`, matching
[`getdesign`](@ref). The compatibility default `view = :full` retains the
complete compiler record. Use `view = :public` for a reader-facing projection
that states fit availability directly while retaining
the scientific raw/constrained parameter layout.
"""
function fit_ready_parameter_layout(spec::FacetSpec;
        preview::Bool = false,
        view::Symbol = :full)
    view in (:full, :public) ||
        throw(ArgumentError("view must be :full or :public"))
    return fit_ready_parameter_layout(getdesign(spec; preview); view)
end

function fit_ready_parameter_layout(design::FacetDesign;
        preview::Bool = false,
        view::Symbol = :full)
    view in (:full, :public) ||
        throw(ArgumentError("view must be :full or :public"))
    preview &&
        throw(ArgumentError("preview is only a FacetSpec compilation option; pass fit_ready_parameter_layout(spec; preview = true)"))
    layout = if _is_mfrm_fixed_q(design.spec)
        _mfrm_fixed_q_parameter_layout(design)
    elseif design.spec.family === :mfrm &&
            design.spec.estimation_status === :fit_supported
        _mfrm_fit_ready_parameter_layout(design)
    elseif design.spec.family === :gmfrm && design.spec.estimation_status === :specified_only
        blueprint = _gmfrm_fit_ready_candidate_blueprint(design)
        _generalized_fit_ready_parameter_layout(design, blueprint)
    elseif design.spec.family === :mgmfrm && design.spec.estimation_status === :specified_only
        blueprint = _mgmfrm_fit_ready_candidate_blueprint(design)
        _generalized_fit_ready_parameter_layout(design, blueprint)
    else
        throw(ArgumentError(
            "fit_ready_parameter_layout currently supports fit-supported MFRM/RSM/PCM " *
            "designs and specified-only GMFRM/MGMFRM preview designs",
        ))
    end
    return view === :public ?
        _public_fit_ready_parameter_layout(layout, design.spec) : layout
end

function _specified_only_preview_parameter_layout(design::FacetDesign)
    block_rows = _block_manifest_rows(design.blocks, design.parameter_names)
    return (;
        schema = "bayesianmgmfrm.fit_ready_parameter_layout.v1",
        family = design.spec.family,
        scope = _spec_scope(design.spec),
        status = design.spec.estimation_status,
        compiler_stage = :specified_only_preview,
        likelihood = :not_fit_ready,
        fit_ready = false,
        public_fit = false,
        experimental_public = false,
        density_space = :not_fit_ready,
        parameterization = :direct_preview,
        n_parameters = length(design.parameter_names),
        parameter_names = copy(design.parameter_names),
        blocks = block_rows,
        n_raw_parameters = length(design.parameter_names),
        raw_parameter_names = copy(design.parameter_names),
        raw_blocks = copy(block_rows),
        n_constrained_parameters = length(design.parameter_names),
        constrained_parameter_names = copy(design.parameter_names),
        constrained_blocks = copy(block_rows),
        transforms = _direct_identity_transform_rows(design),
        constraints = constraint_table(design),
        identification_declarations = identification_declarations(design),
    )
end
