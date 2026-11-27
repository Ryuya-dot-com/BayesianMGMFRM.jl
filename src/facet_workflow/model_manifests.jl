function _design_manifest(design::FacetDesign)
    fixed_coordinates = _stable_fixed_coordinate_rows(design)
    return (;
        n_parameters = length(design.parameter_names),
        parameter_names = copy(design.parameter_names),
        blocks = _design_block_rows(design),
        constraints = constraint_table(design),
        identification_declarations = identification_declarations(design),
        identification = _namedtuple_from_pairs([
            block => design.identification[block]
            for block in sort(collect(keys(design.identification)); by = string)
        ]),
        n_fixed_coordinates = length(fixed_coordinates),
        fixed_coordinates,
        raw_parameterization = _raw_parameterization_manifest(design),
    )
end

function _public_model_availability(spec::FacetSpec)
    _is_mfrm_fixed_q(spec) && return (;
        stability = :experimental, fit_available = true,
        entrypoint = "BayesianMGMFRM.Experimental.fit(spec)",
        claim_scope = :fixed_coefficient_multidimensional_mfrm)
    spec.estimation_status === :fit_supported && return (;
        stability = :stable,
        fit_available = true,
        entrypoint = "BayesianMGMFRM.fit(spec)",
        claim_scope = :minimal_mfrm_rsm_pcm,
    )
    _experimental_generalized_fit_supported(spec) && return (;
        stability = :experimental,
        fit_available = true,
        entrypoint = "BayesianMGMFRM.Experimental.fit(spec)",
        claim_scope = spec.family === :gmfrm ?
            :scalar_rater_consistency_only : :fixed_q_confirmatory_only,
    )
    return (;
        stability = :not_supported,
        fit_available = false,
        entrypoint = missing,
        claim_scope = :specification_and_design_inspection_only,
    )
end

function _public_model_surface_rows(rows, availability)
    return [(;
        family = row.family,
        availability = availability.stability,
        execution_status = availability.stability,
        fit_available = availability.fit_available,
        fit_entrypoint = availability.entrypoint,
        claim_scope = availability.claim_scope,
        block = row.block,
        compiled_role = row.compiled_role,
        source_symbol = row.source_symbol,
        direct_interpretation = row.direct_interpretation,
        raw_coordinate = row.raw_coordinate,
        constrained_block = row.constrained_block,
        constraint = row.constraint,
        transform = row.transform,
        prior = row.prior,
        prior_scale = row.prior_scale,
        prior_parameters = row.prior_parameters,
        report_label = row.report_label,
        parameter_names = copy(row.parameter_names),
        raw_parameter_names = copy(row.raw_parameter_names),
        declaration_status = row.block_status,
        note = row.note,
    ) for row in rows]
end

function _public_raw_parameterization_manifest(design::FacetDesign)
    raw = _raw_parameterization_manifest(design)
    raw === nothing && return nothing
    return (;
        family = raw.family,
        density_space = raw.density_space,
        prior_policy = raw.prior_policy,
        jacobian_policy = raw.jacobian_policy,
        n_raw_parameters = raw.n_raw_parameters,
        raw_parameter_names = copy(raw.raw_parameter_names),
        constrained_parameter_names = copy(raw.constrained_parameter_names),
        raw_blocks = raw.raw_blocks,
        constrained_blocks = raw.constrained_blocks,
        transforms = raw.transforms,
    )
end

const _PUBLIC_ANCHOR_MANIFEST_FIELDS = Set((
    :anchor_scale,
    :anchor_type,
    :block,
    :facet_level,
    :kind,
    :level,
    :parameter,
    :prior_scale,
    :scale,
    :sd,
    :sign,
    :source,
    :source_estimator,
    :source_hash,
    :source_model,
    :source_scale,
    :source_version,
    :target,
    :type,
    :value,
))

function _public_anchor_manifest(anchor::NamedTuple)
    pairs = Pair{Symbol,Any}[]
    for field in keys(anchor)
        field in _PUBLIC_ANCHOR_MANIFEST_FIELDS || continue
        push!(pairs, field => getproperty(anchor, field))
    end
    return (; pairs...)
end

function _public_spec_manifest(spec::FacetSpec)
    manifest = (;
        family = spec.family,
        thresholds = spec.thresholds,
        dimensions = spec.dimensions,
        dimension_labels = copy(spec.dimension_labels),
        discrimination = spec.discrimination,
        q_matrix = _q_matrix_manifest(spec.q_matrix),
        q_matrix_validation = q_matrix_validation(spec),
        validation_bias_terms = copy(spec.validation_bias_terms),
        anchors = [_public_anchor_manifest(anchor) for anchor in spec.anchors],
        availability = _public_model_availability(spec),
        required_facets = (:person, :rater, :item),
        optional_facets = sort(collect(keys(spec.data.optional)); by = string),
        equation = model_equation(spec),
        identification_declarations = identification_declarations(spec),
        constraints = constraint_table(spec),
        prior_blocks = copy(spec.prior_blocks),
    )
    return _is_mfrm_fixed_q(spec) ? merge(manifest, _mfrm_fixed_q_spec_metadata()) : manifest
end

function _public_design_manifest(design::FacetDesign)
    base = _design_manifest(design)
    return (;
        n_parameters = base.n_parameters,
        parameter_names = copy(base.parameter_names),
        blocks = base.blocks,
        constraints = base.constraints,
        identification_declarations = base.identification_declarations,
        identification = base.identification,
        n_fixed_coordinates = base.n_fixed_coordinates,
        fixed_coordinates = base.fixed_coordinates,
        raw_parameterization = _public_raw_parameterization_manifest(design),
    )
end

function _public_model_manifest_projection(value)
    if value isa NamedTuple
        pairs = Pair{Symbol,Any}[]
        for field in keys(value)
            name = lowercase(String(field))
            (field === :next_gate || startswith(name, "internal_") ||
                occursin("fixture_provenance", name) ||
                occursin("repository_path", name)) && continue
            push!(pairs, field => _public_model_manifest_projection(
                getproperty(value, field)))
        end
        return (; pairs...)
    elseif value isa AbstractDict
        output = Dict{String,Any}()
        for (key, item) in value
            field = Symbol(key)
            name = lowercase(String(field))
            (field === :next_gate || startswith(name, "internal_") ||
                occursin("fixture_provenance", name) ||
                occursin("repository_path", name)) && continue
            output[String(key)] = _public_model_manifest_projection(item)
        end
        return output
    elseif value isa AbstractArray
        return map(_public_model_manifest_projection, value)
    elseif value isa Tuple
        return map(_public_model_manifest_projection, value)
    end
    return value
end

"""
    model_manifest(data_or_spec_or_design_or_fit; view = :full)

Return a serializable, report-ready manifest for `FacetData`, `FacetSpec`,
`FacetDesign`, or a fitted MFRM or generalized-model object. The manifest
records facet roles, level maps, category scale, validation status, threshold
structure, deterministic parameter names, block ranges, identification rules,
and data signatures. The compatibility default `view = :full` retains complete
compatibility metadata, including detailed provenance references, and is
intended for private reproduction records. Use `view = :public` when sharing
reader-facing output; that projection keeps scientific model and
parameterization metadata in a concise form.
"""
function model_manifest(data::FacetData; view::Symbol = :full)
    view in (:full, :public) ||
        throw(ArgumentError("view must be :full or :public"))
    return (;
        schema = view === :public ?
            "bayesianmgmfrm.model_manifest_public.v1" :
            "bayesianmgmfrm.model_manifest.v1",
        object = :data,
        data = _data_manifest(data),
        rating_design = view === :public ?
            rating_design_audit(data; view = :public) :
            rating_design_audit(data),
    )
end

function model_manifest(spec::FacetSpec; view::Symbol = :full)
    view in (:full, :public) ||
        throw(ArgumentError("view must be :full or :public"))
    _require_current_facet_spec(spec, "model_manifest")
    if view === :public
        return (;
            schema = "bayesianmgmfrm.model_manifest_public.v1",
            object = :spec,
            data = _data_manifest(spec.data),
            validation = _validation_manifest(spec.validation),
            spec = _public_spec_manifest(spec),
            rating_design = rating_design_audit(spec; view = :public),
        )
    end
    spec_manifest = _spec_manifest(spec)
    return (;
        schema = "bayesianmgmfrm.model_manifest.v1",
        object = :spec,
        status_policy = spec_manifest.status_policy,
        data = _data_manifest(spec.data),
        validation = _validation_manifest(spec.validation),
        spec = spec_manifest,
        rating_design = rating_design_audit(spec),
    )
end

function model_manifest(design::FacetDesign; view::Symbol = :full)
    view in (:full, :public) ||
        throw(ArgumentError("view must be :full or :public"))
    _require_canonical_design(design, "model_manifest")
    spec = design.spec
    if view === :public
        surface_rows = _model_surface_audit(
            design;
            status_policy = _surface_status_policy_for_spec(spec),
        )
        return (;
            schema = "bayesianmgmfrm.model_manifest_public.v1",
            object = :design,
            data = _data_manifest(spec.data),
            validation = _validation_manifest(spec.validation),
            spec = _public_spec_manifest(spec),
            design = _public_design_manifest(design),
            design_identity = design_identity(design),
            model_surface = _public_model_surface_rows(
                surface_rows,
                _public_model_availability(spec),
            ),
            rating_design = rating_design_audit(design; view = :public),
        )
    end
    spec_manifest = _spec_manifest(spec)
    return (;
        schema = "bayesianmgmfrm.model_manifest.v1",
        object = :design,
        status_policy = spec_manifest.status_policy,
        data = _data_manifest(spec.data),
        validation = _validation_manifest(spec.validation),
        spec = spec_manifest,
        design = _design_manifest(design),
        design_identity = design_identity(design),
        model_surface_audit = model_surface_audit(design),
        rating_design = rating_design_audit(design),
    )
end
