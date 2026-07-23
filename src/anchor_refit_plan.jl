# anchor_refit_plan.jl -- preflight contract for future anchor-constrained refits.

_anchor_refit_spec(spec::FacetSpec) = spec
_anchor_refit_spec(design::FacetDesign) = design.spec

const _ANCHOR_REFIT_SOURCE_IDENTIFIER = r"^[A-Za-z][A-Za-z0-9_.-]{0,63}$"
const _ANCHOR_REFIT_SOURCE_MODELS = (:mfrm_rsm, :mfrm_pcm)
const _ANCHOR_REFIT_SOURCE_ESTIMATORS = (:jml, :pmle, :mml, :mcmc)
# In the version-1 declaration, the legacy `source_scale` and `sign` fields
# describe the already transformed anchor value in destination coordinates.
# Original source scale/sign and the applied transform belong in the artifact
# identified by `source_hash` until a later schema gives them separate fields.
const _ANCHOR_REFIT_VALUE_SCALES = (:logit,)
const _ANCHOR_REFIT_VALUE_SIGNS = (:severity_positive, :difficulty_positive)
const _ANCHOR_REFIT_SHA256 = r"^(?:sha256:)?[0-9a-f]{64}$"

function _anchor_refit_canonical_block(block::Symbol)
    block in (:rater, :rater_severity, :raters) && return :rater
    block in (:item, :item_difficulty, :items) && return :item
    block in (:person, :person_location, :persons) && return :person
    block in (:thresholds, :threshold_steps, :steps) && return :thresholds
    return :unknown
end

function _anchor_refit_levels(data::FacetData, block::Symbol)
    block === :rater && return data.rater_levels
    block === :item && return data.item_levels
    block === :person && return data.person_levels
    block === :thresholds && return data.category_levels
    return Any[]
end

function _anchor_refit_metadata(anchor, key::Symbol)
    return haskey(anchor, key) ? anchor[key] : missing
end

function _anchor_refit_source_valid(value)
    text = value isa Symbol ? String(value) :
        value isa AbstractString ? String(value) : nothing
    return text !== nothing && occursin(_ANCHOR_REFIT_SOURCE_IDENTIFIER, text)
end

function _anchor_refit_version_valid(value)
    value isa AbstractString || return false
    text = String(value)
    isempty(text) && return false
    ncodeunits(text) <= 128 || return false
    strip(text) == text || return false
    return all(isprint, text)
end

function _anchor_refit_hash_valid(value)
    return value isa AbstractString &&
        occursin(_ANCHOR_REFIT_SHA256, String(value))
end

function _anchor_refit_expected_model(thresholds::Symbol)
    thresholds === :rating_scale && return :mfrm_rsm
    thresholds === :partial_credit && return :mfrm_pcm
    return :unknown
end

function _anchor_refit_expected_sign(block::Symbol)
    block === :rater && return :severity_positive
    block === :item && return :difficulty_positive
    return :unknown
end

function _anchor_refit_push_invalid!(invalid_fields, issues, field, issue)
    field in invalid_fields || push!(invalid_fields, field)
    issue in issues || push!(issues, issue)
    return nothing
end

function _anchor_refit_provenance(anchor, canonical_block::Symbol,
        thresholds::Symbol)
    source = _anchor_refit_metadata(anchor, :source)
    source_version = _anchor_refit_metadata(anchor, :source_version)
    source_model = _anchor_refit_metadata(anchor, :source_model)
    source_estimator = _anchor_refit_metadata(anchor, :source_estimator)
    source_hash = _anchor_refit_metadata(anchor, :source_hash)
    source_scale = _anchor_refit_metadata(anchor, :source_scale)
    sign = _anchor_refit_metadata(anchor, :sign)
    missing_fields = Symbol[]
    ismissing(source) && push!(missing_fields, :source)
    ismissing(source_version) && push!(missing_fields, :source_version)
    ismissing(source_model) && push!(missing_fields, :source_model)
    ismissing(source_estimator) && push!(missing_fields, :source_estimator)
    ismissing(source_hash) && push!(missing_fields, :source_hash)
    ismissing(source_scale) && push!(missing_fields, :source_scale)
    ismissing(sign) && push!(missing_fields, :sign)

    invalid_fields = Symbol[]
    issues = Symbol[]
    if !ismissing(source) && !_anchor_refit_source_valid(source)
        _anchor_refit_push_invalid!(invalid_fields, issues, :source,
            :source_must_be_machine_identifier)
    end
    if !ismissing(source_version) &&
            !_anchor_refit_version_valid(source_version)
        _anchor_refit_push_invalid!(invalid_fields, issues, :source_version,
            :source_version_must_be_nonempty_printable_string)
    end
    if !ismissing(source_model)
        if !(source_model isa Symbol &&
                source_model in _ANCHOR_REFIT_SOURCE_MODELS)
            _anchor_refit_push_invalid!(invalid_fields, issues, :source_model,
                :source_model_not_supported)
        elseif source_model !== _anchor_refit_expected_model(thresholds)
            _anchor_refit_push_invalid!(invalid_fields, issues, :source_model,
                :source_model_threshold_regime_mismatch)
        end
    end
    if !ismissing(source_estimator) &&
            !(source_estimator isa Symbol &&
                source_estimator in _ANCHOR_REFIT_SOURCE_ESTIMATORS)
        _anchor_refit_push_invalid!(invalid_fields, issues, :source_estimator,
            :source_estimator_not_supported)
    end
    if !ismissing(source_hash) && !_anchor_refit_hash_valid(source_hash)
        _anchor_refit_push_invalid!(invalid_fields, issues, :source_hash,
            :source_hash_must_be_lowercase_sha256)
    end
    if !ismissing(source_scale) &&
            !(source_scale isa Symbol &&
                source_scale in _ANCHOR_REFIT_VALUE_SCALES)
        _anchor_refit_push_invalid!(invalid_fields, issues, :source_scale,
            :source_scale_not_supported)
    end
    if !ismissing(sign)
        if !(sign isa Symbol && sign in _ANCHOR_REFIT_VALUE_SIGNS)
            _anchor_refit_push_invalid!(invalid_fields, issues, :sign,
                :sign_not_supported)
        elseif canonical_block in (:rater, :item) &&
                sign !== _anchor_refit_expected_sign(canonical_block)
            _anchor_refit_push_invalid!(invalid_fields, issues, :sign,
                :sign_incompatible_with_anchor_block)
        end
    end
    return (;
        source,
        source_version,
        source_model,
        source_estimator,
        source_hash,
        source_scale,
        sign,
        missing_fields = Tuple(missing_fields),
        invalid_fields = Tuple(invalid_fields),
        issues = Tuple(issues),
        complete = isempty(missing_fields) && isempty(invalid_fields),
    )
end

function _anchor_refit_value_check(value)
    value isa Bool && return (;
        valid = false,
        normalized = missing,
        issue = :anchor_value_boolean_not_allowed,
    )
    value isa Real || return (;
        valid = false,
        normalized = missing,
        issue = :anchor_value_must_be_real,
    )
    finite = try
        isfinite(value)
    catch
        false
    end
    finite || return (;
        valid = false,
        normalized = missing,
        issue = :anchor_value_not_finite,
    )
    normalized = try
        Float64(value)
    catch
        nothing
    end
    normalized === nothing && return (;
        valid = false,
        normalized = missing,
        issue = :anchor_value_not_float64_representable,
    )
    isfinite(normalized) || return (;
        valid = false,
        normalized = missing,
        issue = :anchor_value_not_float64_representable,
    )
    underflowed = try
        iszero(normalized) && !iszero(value)
    catch
        true
    end
    underflowed && return (;
        valid = false,
        normalized = missing,
        issue = :anchor_value_underflows_float64,
    )
    return (; valid = true, normalized, issue = nothing)
end

function _anchor_refit_scale_check(anchor)
    declared = _anchor_symbol(anchor, (:scale, :sd, :prior_scale))
    if anchor.anchor_type === :hard_anchor
        return (;
            declared,
            valid = declared === nothing,
            normalized = missing,
            issue = declared === nothing ? nothing :
                :hard_anchor_must_not_declare_prior_scale,
        )
    end
    declared isa Bool && return (;
        declared,
        valid = false,
        normalized = missing,
        issue = :soft_anchor_scale_boolean_not_allowed,
    )
    declared isa Real || return (;
        declared,
        valid = false,
        normalized = missing,
        issue = :soft_anchor_scale_must_be_real,
    )
    finite_positive = try
        isfinite(declared) && declared > 0
    catch
        false
    end
    finite_positive || return (;
        declared,
        valid = false,
        normalized = missing,
        issue = :soft_anchor_scale_must_be_positive_finite,
    )
    normalized = try
        Float64(declared)
    catch
        nothing
    end
    if normalized === nothing || !isfinite(normalized) || normalized <= 0
        return (;
            declared,
            valid = false,
            normalized = missing,
            issue = :soft_anchor_scale_not_float64_representable,
        )
    end
    return (; declared, valid = true, normalized, issue = nothing)
end

function _anchor_refit_initial_row(spec::FacetSpec, anchor, index::Int;
        require_provenance::Bool)
    canonical_block = _anchor_refit_canonical_block(anchor.block)
    target = _anchor_target(anchor)
    levels = _anchor_refit_levels(spec.data, canonical_block)
    target_found = ismissing(target) ? false :
        any(level -> isequal(level, target), levels)
    value_check = _anchor_refit_value_check(anchor.value)
    value_valid = value_check.valid
    scale_check = _anchor_refit_scale_check(anchor)
    provenance = _anchor_refit_provenance(
        anchor,
        canonical_block,
        spec.thresholds,
    )
    issues = Symbol[]
    canonical_block in (:rater, :item) || push!(issues,
        canonical_block === :unknown ? :unknown_anchor_block :
        :block_deferred_from_first_hard_anchor_slice)
    ismissing(target) && push!(issues, :explicit_target_required)
    !ismissing(target) && !target_found && push!(issues, :target_not_in_data)
    value_valid || push!(issues, value_check.issue)
    if anchor.anchor_type === :hard_anchor
        scale_check.valid || push!(issues, scale_check.issue)
    else
        push!(issues, :soft_anchor_deferred)
        scale_check.valid || push!(issues, scale_check.issue)
        target_found && !isempty(levels) && isequal(target, first(levels)) &&
            push!(issues,
                :soft_anchor_on_reference_level_requires_reparameterization)
    end
    require_provenance && !isempty(provenance.missing_fields) &&
        push!(issues, :anchor_provenance_incomplete)
    !isempty(provenance.invalid_fields) &&
        push!(issues, :anchor_provenance_invalid)
    status = isempty(issues) ? :candidate_supported :
        :soft_anchor_deferred in issues && length(issues) == 1 ?
            :deferred_soft_anchor : :preflight_failed
    return (;
        anchor_index = index,
        declared_block = anchor.block,
        canonical_block,
        target,
        target_found,
        anchor_type = anchor.anchor_type,
        value = anchor.value,
        value_valid,
        normalized_value = value_check.normalized,
        value_issue = value_check.issue,
        scale = anchor.anchor_scale,
        declared_scale = scale_check.declared,
        scale_valid = scale_check.valid,
        normalized_scale = scale_check.normalized,
        scale_issue = scale_check.issue,
        provenance.source,
        provenance.source_version,
        provenance.source_model,
        provenance.source_estimator,
        provenance.source_hash,
        source_hash_format_valid = _anchor_refit_hash_valid(
            provenance.source_hash,
        ),
        source_bytes_verified = false,
        provenance.source_scale,
        provenance.sign,
        provenance_complete = provenance.complete,
        missing_provenance_fields = provenance.missing_fields,
        invalid_provenance_fields = provenance.invalid_fields,
        provenance_issues = provenance.issues,
        duplicate_target = false,
        conflicting_value = false,
        issues = Tuple(issues),
        status,
    )
end

function _anchor_refit_duplicate_rows(rows)
    target_indices = Dict{Tuple{Symbol,Any},Vector{Int}}()
    for (index, row) in pairs(rows)
        ismissing(row.target) && continue
        key = (row.canonical_block, row.target)
        push!(get!(target_indices, key, Int[]), index)
    end
    duplicate = falses(length(rows))
    conflict = falses(length(rows))
    for indices in values(target_indices)
        length(indices) > 1 || continue
        duplicate[indices] .= true
        values_at_target = [
            rows[index].value_valid ?
                rows[index].normalized_value : rows[index].value
            for index in indices
        ]
        conflicting = any(value -> !isequal(value, first(values_at_target)),
            values_at_target[2:end])
        conflicting && (conflict[indices] .= true)
    end
    out = NamedTuple[]
    for (index, row) in pairs(rows)
        issues = Symbol[row.issues...]
        if duplicate[index]
            push!(issues, conflict[index] ?
                :conflicting_anchor_values : :duplicate_anchor_target)
        end
        push!(out, merge(row, (;
            duplicate_target = duplicate[index],
            conflicting_value = conflict[index],
            issues = Tuple(unique(issues)),
            status = isempty(issues) ? :candidate_supported :
                :soft_anchor_deferred in issues && length(issues) == 1 ?
                    :deferred_soft_anchor : :preflight_failed,
        )))
    end
    return out
end

function _anchor_refit_family_issues(spec::FacetSpec)
    issues = Symbol[]
    spec.family === :mfrm || push!(issues, :generalized_family_deferred)
    spec.dimensions == 1 || push!(issues, :multidimensional_anchor_refit_deferred)
    spec.discrimination === :none ||
        push!(issues, :discrimination_anchor_refit_deferred)
    return Tuple(issues)
end

"""
    anchor_refit_plan(spec_or_design; require_provenance = true)

Return a machine-readable preflight plan for anchor-constrained re-estimation.
The first implementation target is deliberately narrow: explicit individual
hard anchors on rater severity or item difficulty in the minimal Bayesian
MFRM/RSM/PCM family. Each candidate anchor is checked for a finite value, an
observed level, duplicate or conflicting declarations, and typed source,
version, model, estimator, SHA-256, source-scale, and sign provenance. Boolean
values and finite numbers that cannot be represented as finite `Float64`
coordinates are rejected. `require_provenance = false` permits absent
provenance, but any provenance field that is supplied must still satisfy the
fail-closed field contract.

The version-1 `source_scale` and `sign` fields describe the already transformed
anchor value in destination logit coordinates. Original source scale/sign and
the applied transform must be preserved in the artifact named by `source_hash`.
Only the lowercase SHA-256 string format is checked; source bytes are not
verified by this preflight.

An explicit hard anchor must not also declare `scale`, `sd`, or `prior_scale`.
A soft anchor on the current first-level-zero rater/item reference is rejected
because its prior would be constant under that gauge; a future implementation
must reparameterize the reference or transform the source anchor to an
identified contrast.

The planned hard-anchor implementation replaces the current reference gauge
with an affine direct-parameter map, removes fixed coordinates from the sampled
vector, and restores fixed values in posterior reports. It must not add a
zero-variance prior or silently stack anchors on top of the existing reference
constraint. Soft anchors remain a later, sensitivity-tested prior feature.

This function performs no fit and does not change `FacetSpec.estimation_status`.
It records whether a declaration is ready for the future numerical hard-anchor
slice and the comparison gates an anchored refit must pass.
"""
function anchor_refit_plan(spec_or_design; require_provenance::Bool = true)
    spec = _anchor_refit_spec(spec_or_design)
    initial_rows = [
        _anchor_refit_initial_row(spec, anchor, index; require_provenance)
        for (index, anchor) in pairs(spec.anchors)
    ]
    rows = _anchor_refit_duplicate_rows(initial_rows)
    family_issues = _anchor_refit_family_issues(spec)
    n_hard = count(row -> row.anchor_type === :hard_anchor, rows)
    n_soft = count(row -> row.anchor_type === :soft_anchor, rows)
    n_failed = count(row -> row.status !== :candidate_supported, rows)
    candidate_supported = !isempty(rows) && isempty(family_issues) &&
        n_failed == 0 && n_soft == 0
    status = isempty(rows) ? :no_anchors_declared :
        candidate_supported ? :hard_anchor_candidate_ready : :preflight_failed

    return (;
        schema = "bayesianmgmfrm.anchor_refit_plan.v1",
        object = :anchor_refit_plan,
        family = spec.family,
        thresholds = spec.thresholds,
        dimensions = spec.dimensions,
        discrimination = spec.discrimination,
        estimation_status = spec.estimation_status,
        current_implementation = :declaration_and_diagnostics_only,
        numerical_refit_implemented = false,
        require_provenance,
        n_anchors = length(rows),
        n_hard_anchors = n_hard,
        n_soft_anchors = n_soft,
        n_failed_anchors = n_failed,
        family_issues,
        anchor_rows = Tuple(rows),
        candidate_supported,
        status,
        provenance_contract = (;
            version = :v1_normalized_value,
            source_scale_semantics =
                :normalized_anchor_value_destination_scale,
            sign_semantics =
                :normalized_anchor_value_destination_orientation,
            accepted_value_scale = :logit,
            accepted_rater_sign = :severity_positive,
            accepted_item_sign = :difficulty_positive,
            original_source_and_transform_location =
                :artifact_identified_by_source_hash,
            source_hash_check = :lowercase_sha256_format_only,
            source_bytes_verified = false,
            provenance_complete_semantics =
                :required_fields_present_and_field_contract_valid,
            split_original_and_destination_fields = :future_schema,
        ),
        hard_anchor_contract = (;
            first_slice = :individual_rater_and_item_hard_anchors,
            coordinate_strategy = :affine_direct_parameter_map,
            identification_policy = :replace_reference_gauge_not_stack_constraints,
            prior_scale_declaration_allowed = false,
            fixed_coordinates_sampled = false,
            full_direct_draws_restored_for_reports = true,
            exact_fixed_value_check_required = true,
            rank_and_overconstraint_check_required = true,
        ),
        soft_anchor_contract = (;
            status = :deferred,
            strategy = :proper_normal_prior_on_identified_direct_parameter,
            structural_gauge_retained = true,
            prior_scale_required = true,
            prior_sensitivity_required = true,
            hard_soft_mixing_policy_required = true,
            current_reference_level_policy =
                :reject_until_reparameterized_or_source_contrast_transformed,
        ),
        comparison_gates = (
            :constraint_rank_and_exactness,
            :sampler_quality,
            :nonanchor_parameter_recovery,
            :posterior_shift_against_unanchored_fit,
            :heldout_predictive_performance,
            :posterior_predictive_category_replication,
            :rater_linking_connectivity,
            :predeclared_anchor_sensitivity,
        ),
        caveat = :plan_only_does_not_execute_anchor_constrained_refit,
        next_gate = candidate_supported ?
            :implement_minimal_mfrm_hard_anchor_affine_map :
            :resolve_anchor_refit_preflight,
    )
end
