# model_contract.jl -- canonical spec/design identity and execution snapshots

using SHA

const _MODEL_CONTRACT_SCHEMA = "bayesianmgmfrm.design_identity.v1"

function _model_contract_update!(context, text::AbstractString)
    SHA.update!(context, codeunits(text))
    return context
end

function _model_contract_sort_key(value)
    value isa Symbol && return "symbol:" * String(value)
    value isa AbstractString && return "string:" * repr(String(value))
    value isa Integer && return "integer:" * string(typeof(value)) * ":" *
        string(value)
    return string(typeof(value)) * ":" * repr(value)
end

function _model_contract_update_value!(context, value)
    if value === nothing
        return _model_contract_update!(context, "nothing")
    elseif value === missing
        return _model_contract_update!(context, "missing")
    elseif value isa Bool
        return _model_contract_update!(context,
            value ? "bool:true" : "bool:false")
    elseif value isa Symbol
        return _model_contract_update!(context, "symbol:" * String(value))
    elseif value isa AbstractString
        return _model_contract_update!(context,
            "string:" * repr(String(value)))
    elseif value isa Integer
        return _model_contract_update!(context,
            "integer:" * string(typeof(value)) * ":" * string(value))
    elseif value isa AbstractFloat
        return _model_contract_update!(context,
            "float:" * string(typeof(value)) * ":" * repr(value))
    elseif value isa NamedTuple
        _model_contract_update!(context, "namedtuple:(")
        names = propertynames(value)
        for (index, name) in pairs(names)
            index > 1 && _model_contract_update!(context, ",")
            _model_contract_update!(context, String(name) * "=")
            _model_contract_update_value!(context, getproperty(value, name))
        end
        return _model_contract_update!(context, ")")
    elseif value isa AbstractDict
        _model_contract_update!(context, "dict:{")
        keys_sorted = sort!(collect(keys(value)); by = _model_contract_sort_key)
        for (index, key) in pairs(keys_sorted)
            index > 1 && _model_contract_update!(context, ",")
            _model_contract_update_value!(context, key)
            _model_contract_update!(context, "=>")
            _model_contract_update_value!(context, value[key])
        end
        return _model_contract_update!(context, "}")
    elseif value isa AbstractArray
        _model_contract_update!(context, "array:size=" * repr(size(value)) * ":[")
        for (index, entry) in enumerate(value)
            index > 1 && _model_contract_update!(context, ",")
            _model_contract_update_value!(context, entry)
        end
        return _model_contract_update!(context, "]")
    elseif value isa Tuple
        _model_contract_update!(context, "tuple:(")
        for (index, entry) in pairs(value)
            index > 1 && _model_contract_update!(context, ",")
            _model_contract_update_value!(context, entry)
        end
        return _model_contract_update!(context, ")")
    end
    return _model_contract_update!(context,
        "value:" * string(typeof(value)) * ":" * repr(value))
end

function _current_spec_components(spec::FacetSpec)
    data = spec.data
    report = spec.validation
    spec.thresholds in (:rating_scale, :partial_credit) ||
        throw(ArgumentError(
            "FacetSpec thresholds must be :rating_scale or :partial_credit",
        ))
    report.n == data.n || throw(ArgumentError(
        "FacetSpec validation row count is stale: report has $(report.n), " *
        "but FacetData has $(data.n)",
    ))
    report.data_signature == _data_signature(data) || throw(ArgumentError(
        "FacetSpec data changed after validation; construct a new FacetData, " *
        "rerun validate_design, and rebuild the specification",
    ))
    report.passed || throw(ArgumentError(
        "FacetSpec contains a validation report that did not pass",
    ))

    family = _check_family(spec.family)
    dimensions = _check_dimensions(family, spec.dimensions)
    dimension_labels =
        _normalize_dimension_labels(dimensions, spec.dimension_labels)
    discrimination = _check_discrimination(family, spec.discrimination)
    q_matrix = _normalize_q_matrix(
        data,
        family,
        dimensions,
        spec.q_matrix,
        dimension_labels,
    )
    validation_bias_terms =
        _normalize_bias_terms(spec.validation_bias_terms, report)
    anchors = _normalize_anchors(spec.anchors)
    estimation_status = _estimation_status(
        family,
        dimensions,
        discrimination,
        q_matrix,
        anchors,
    )
    constraints = _constraint_rows(;
        family,
        thresholds = spec.thresholds,
        dimensions,
        dimension_labels,
        discrimination,
        q_matrix,
        validation_bias_terms,
        anchors,
        estimation_status,
    )
    prior_blocks = _prior_rows(family, dimensions, discrimination)
    return (;
        family,
        dimensions,
        dimension_labels,
        discrimination,
        q_matrix,
        validation_bias_terms,
        anchors,
        estimation_status,
        constraints,
        prior_blocks,
    )
end

function _require_current_facet_spec(spec::FacetSpec, caller::AbstractString)
    expected = try
        _current_spec_components(spec)
    catch err
        err isa ArgumentError || rethrow()
        throw(ArgumentError("$caller rejected a stale or noncanonical FacetSpec: " *
            sprint(showerror, err)))
    end

    checks = (
        (:dimension_labels, spec.dimension_labels, expected.dimension_labels),
        (:q_matrix, spec.q_matrix, expected.q_matrix),
        (:validation_bias_terms, spec.validation_bias_terms,
            expected.validation_bias_terms),
        (:anchors, spec.anchors, expected.anchors),
        (:estimation_status, spec.estimation_status,
            expected.estimation_status),
        (:constraints, spec.constraints, expected.constraints),
        (:prior_blocks, spec.prior_blocks, expected.prior_blocks),
    )
    for (field, observed, canonical) in checks
        isequal(observed, canonical) && continue
        throw(ArgumentError(
            "$caller rejected a stale or noncanonical FacetSpec field :$field; " *
            "rebuild the specification with mfrm_spec",
        ))
    end
    return nothing
end

function _canonical_design_for_spec(spec::FacetSpec)
    spec.estimation_status === :fit_supported && return _minimal_design(spec)
    spec.estimation_status === :specified_only && return _preview_design(spec)
    throw(ArgumentError(
        "unsupported FacetSpec estimation_status :$(spec.estimation_status)",
    ))
end

function _require_canonical_design(design::FacetDesign, caller::AbstractString)
    _require_current_facet_spec(design.spec, caller)
    expected = _canonical_design_for_spec(design.spec)
    design.parameter_names == expected.parameter_names || throw(ArgumentError(
        "$caller rejected a noncanonical FacetDesign parameter order; " *
        "recompile it with getdesign",
    ))
    design.blocks == expected.blocks || throw(ArgumentError(
        "$caller rejected noncanonical FacetDesign block ranges; " *
        "recompile it with getdesign",
    ))
    design.identification == expected.identification || throw(ArgumentError(
        "$caller rejected noncanonical FacetDesign identification metadata; " *
        "recompile it with getdesign",
    ))
    return nothing
end

function _design_identity_payload(design::FacetDesign)
    data = design.spec.data
    optional_roles = sort!(collect(keys(data.optional)); by = string)
    block_names = sort!(collect(keys(design.blocks)); by = string)
    identification_names =
        sort!(collect(keys(design.identification)); by = string)
    return (;
        schema = _MODEL_CONTRACT_SCHEMA,
        data = (;
            n = data.n,
            person = data.person,
            rater = data.rater,
            item = data.item,
            score = data.score,
            category = data.category,
            person_levels = data.person_levels,
            rater_levels = data.rater_levels,
            item_levels = data.item_levels,
            category_levels = data.category_levels,
            optional = [(;
                role,
                index = data.optional[role],
                levels = data.optional_levels[role],
            ) for role in optional_roles],
            columns = data.columns,
        ),
        validation = (;
            n = design.spec.validation.n,
            passed = design.spec.validation.passed,
            issues = [(issue.code, issue.severity)
                for issue in design.spec.validation.issues],
        ),
        spec = (;
            thresholds = design.spec.thresholds,
            family = design.spec.family,
            dimensions = design.spec.dimensions,
            dimension_labels = design.spec.dimension_labels,
            discrimination = design.spec.discrimination,
            q_matrix = design.spec.q_matrix,
            validation_bias_terms = design.spec.validation_bias_terms,
            anchors = design.spec.anchors,
            constraints = design.spec.constraints,
            prior_blocks = design.spec.prior_blocks,
            estimation_status = design.spec.estimation_status,
        ),
        design = (;
            parameter_names = design.parameter_names,
            blocks = [(block, design.blocks[block]) for block in block_names],
            identification = [(block, design.identification[block])
                for block in identification_names],
        ),
    )
end

function _canonical_design_fingerprint(design::FacetDesign)
    context = SHA.SHA2_256_CTX()
    _model_contract_update_value!(context, _design_identity_payload(design))
    return bytes2hex(SHA.digest!(context))
end

"""
    design_identity(design::FacetDesign)
    design_identity(spec::FacetSpec; preview = false)

Validate that a specification still matches its original data-validation
contract and that a design exactly matches the package compiler output. Return
a canonical SHA-256 identity for the data, model specification, parameter
order, block ranges, and identification declarations.

The identity is suitable for provenance comparisons and stale-object guards.
It is not a hash of posterior draws or a substitute for a fit-cache identity.
"""
function design_identity(design::FacetDesign)
    _require_canonical_design(design, "design_identity")
    return (;
        schema = _MODEL_CONTRACT_SCHEMA,
        object = :facet_design,
        algorithm = :sha256,
        value = _canonical_design_fingerprint(design),
        family = design.spec.family,
        thresholds = design.spec.thresholds,
        dimensions = design.spec.dimensions,
        estimation_status = design.spec.estimation_status,
        data_signature = design.spec.validation.data_signature,
        n_observations = design.spec.data.n,
        n_parameters = length(design.parameter_names),
        canonical = true,
        snapshot_policy = :validated_deepcopy_at_numerical_entry,
    )
end

function design_identity(spec::FacetSpec; preview::Bool = false)
    return design_identity(getdesign(spec; preview))
end

function _validated_design_snapshot(design::FacetDesign,
        caller::AbstractString)
    _require_canonical_design(design, caller)
    snapshot = deepcopy(design)
    _require_canonical_design(snapshot, caller)
    return snapshot
end
