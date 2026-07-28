module LocalDependencePilotCalibrationSemantics

using JSON3
using SHA

import BayesianMGMFRM

include(joinpath(@__DIR__, "local_json.jl"))

export LD1B1_EXPECTED_PLAN_ROWS,
    LD1B1_ORDERED_JOB_ROWS_SHA256,
    LD1B1_PILOT_CONTRACT_SHA256,
    ld1b1_canonical_generation_failed_row,
    ld1b1_load_calibration_semantic_context,
    ld1b1_nonterminal_artifact_failure_codes,
    ld1b1_normalized_json,
    ld1b1_normalized_json_sha256,
    ld1b1_semantic_json_native,
    ld1b1_validate_calibration_member,
    ld1b1_validate_completed_diagnostic_calibration_link,
    ld1b1_validate_generation_failed_member

const LD1B1_PROTOCOL_SCHEMA =
    "bayesianmgmfrm.local_dependence_pilot_protocol_preflight.v1"
const LD1B1_EXPECTED_PLAN_ROWS = 660
const LD1B1_PILOT_CONTRACT_SHA256 =
    "a651515317e0b7636ce47d4e56776c4017d1e6293e3185607c377915f6ad2e5a"
const LD1B1_ORDERED_JOB_ROWS_SHA256 =
    "71eb1f33bb2bdc05495b748608c32af50334216ae607e6ae2be8d50cbf9be574"
const _LD1B1_NONTERMINAL_ARTIFACT_FAILURE_CODES = (
    :sampler_diagnostics_unavailable,
    :final_calibration_serialization_failed,
)

"""
    ld1b1_nonterminal_artifact_failure_codes()

Return the frozen failure codes that describe incomplete artifact production,
not terminal scientific outcomes. These codes may only be recovered or retired
as partial attempts; they must never appear in a sealed terminal failure row.
"""
ld1b1_nonterminal_artifact_failure_codes() =
    _LD1B1_NONTERMINAL_ARTIFACT_FAILURE_CODES

const _LD1B1_DATA_SIGNATURE_PATTERN = r"^(0|[1-9][0-9]{0,19})$"

_ld1b1_string(value) = String(value)

"""
Decode a native or persisted LD1b1 data signature without precision loss.

Public Julia objects carry the signature as `UInt64`. Persisted semantic JSON
must carry the exact unsigned value as a canonical decimal string so JSON3
cannot coerce values above `typemax(Int64)` to `Float64`.
"""
function _ld1b1_data_signature(value, label::AbstractString)
    value isa UInt64 && return value
    value isa AbstractString || throw(ArgumentError(
        "$label must be a native UInt64 or canonical decimal string"))
    text = String(value)
    occursin(_LD1B1_DATA_SIGNATURE_PATTERN, text) || throw(ArgumentError(
        "$label is not a canonical decimal UInt64 string"))
    parsed = tryparse(UInt64, text)
    parsed === nothing && throw(ArgumentError(
        "$label is outside the UInt64 range"))
    string(parsed) == text || throw(ArgumentError(
        "$label is not the canonical decimal UInt64 representation"))
    return parsed
end

function ld1b1_semantic_json_native(value,
        field::Union{Nothing,Symbol,String} = nothing)
    if field !== nothing && String(field) == "data_signature"
        return string(_ld1b1_data_signature(value, "data signature"))
    elseif value === nothing || ismissing(value)
        return nothing
    elseif value isa Symbol
        return String(value)
    elseif value isa NamedTuple || value isa AbstractDict
        return Dict{String,Any}(
            String(key) => ld1b1_semantic_json_native(element, key)
            for (key, element) in pairs(value)
        )
    elseif value isa AbstractArray || value isa Tuple
        return Any[
            ld1b1_semantic_json_native(element, field) for element in value]
    end
    return value
end

function ld1b1_normalized_json(value)
    io = IOBuffer()
    write_canonical_json(io, ld1b1_semantic_json_native(value))
    return String(take!(io))
end

ld1b1_normalized_json_sha256(value) =
    bytes2hex(sha256(codeunits(ld1b1_normalized_json(value))))

function _ld1b1_int(value, label::AbstractString)
    value isa Integer && !(value isa Bool) ||
        throw(ArgumentError("$label must be an integer"))
    return Int(value)
end

function _ld1b1_bool(value, label::AbstractString)
    value isa Bool || throw(ArgumentError("$label must be boolean"))
    return value
end

function _ld1b1_require_sha256(value, label::AbstractString)
    text = _ld1b1_string(value)
    occursin(r"^[0-9a-f]{64}$", text) ||
        throw(ArgumentError("$label is not a SHA-256 digest"))
    return text
end

function _ld1b1_require_exact_keys(value, expected::Tuple,
        label::AbstractString)
    observed = Set(String(key) for key in keys(value))
    required = Set(String(key) for key in expected)
    length(keys(value)) == length(expected) && observed == required ||
        throw(ArgumentError("$label has an unexpected field set"))
    return nothing
end

function _ld1b1_field(value, field::Symbol, label::AbstractString)
    if value isa NamedTuple
        hasproperty(value, field) ||
            throw(ArgumentError("$label lacks field $field"))
        return getproperty(value, field)
    end
    matching_keys = [key for key in keys(value)
        if key === field || key == String(field)]
    length(matching_keys) == 1 || throw(ArgumentError(
        isempty(matching_keys) ? "$label lacks field $field" :
        "$label has ambiguous symbol/string keys for field $field"))
    return value[only(matching_keys)]
end

function _ld1b1_verify_protocol_content_hash(protocol)
    native = ld1b1_semantic_json_native(protocol)
    haskey(native, "content_hash") ||
        throw(ArgumentError("protocol artifact lacks a content hash"))
    record = pop!(native, "content_hash")
    _ld1b1_require_exact_keys(record,
        (:algorithm, :value, :covers, :canonical_format),
        "protocol content-hash record")
    _ld1b1_string(record["algorithm"]) == "sha256" ||
        throw(ArgumentError("protocol content hash does not use SHA-256"))
    _ld1b1_string(record["covers"]) ==
        "artifact_without_content_hash" || throw(ArgumentError(
        "protocol content hash has the wrong coverage"))
    _ld1b1_string(record["canonical_format"]) ==
        "local_json_sorted_compact" || throw(ArgumentError(
        "protocol content hash has the wrong canonical format"))
    stored = _ld1b1_require_sha256(
        record["value"], "protocol content hash")
    recomputed = ld1b1_normalized_json_sha256(native)
    stored == recomputed ||
        throw(ArgumentError("protocol content hash does not match its contents"))
    return stored
end

function _ld1b1_canonical_job_id(plan)
    replication = lpad(string(plan.replication), 2, '0')
    scenario_index = lpad(string(plan.scenario_index), 2, '0')
    return string(
        "ld1b1_pilot__rep", replication,
        "__s", scenario_index,
        "__", plan.scenario_id,
    )
end

"""
    ld1b1_load_calibration_semantic_context(protocol_path)

Reconstruct the frozen 660-row LD1b1 pilot plan from the protocol artifact
using the public planning APIs. The artifact contract, complete public
preflight, compact job rows, and frozen contract/job hashes must agree exactly.
This function generates no response data and performs no fitting or MCMC.
"""
function ld1b1_load_calibration_semantic_context(
        protocol_path::AbstractString)
    isfile(protocol_path) ||
        throw(ArgumentError("protocol artifact is missing: $protocol_path"))
    protocol = JSON3.read(read(protocol_path, String))
    _ld1b1_string(protocol[:schema]) == LD1B1_PROTOCOL_SCHEMA ||
        throw(ArgumentError("unexpected LD1b1 protocol schema"))
    _ld1b1_string(protocol[:status]) ==
        "pilot_protocol_preflight_passed" || throw(ArgumentError(
        "LD1b1 protocol preflight did not pass"))
    _ld1b1_bool(protocol[:summary][:passed], "protocol summary passed") ||
        throw(ArgumentError("LD1b1 protocol summary did not pass"))
    protocol_content_hash = _ld1b1_verify_protocol_content_hash(protocol)

    pilot_contract =
        BayesianMGMFRM.local_dependence_calibration_pilot_contract()
    public_contract_sha256 =
        ld1b1_normalized_json_sha256(pilot_contract)
    artifact_contract_sha256 =
        ld1b1_normalized_json_sha256(protocol[:pilot_contract])
    public_contract_sha256 == artifact_contract_sha256 ==
        LD1B1_PILOT_CONTRACT_SHA256 || throw(ArgumentError(
        "protocol pilot contract differs from the frozen public contract"))

    preflight = protocol[:pilot_preflight]
    planning = pilot_contract.planning
    dimensions = planning.base_dimensions
    plan_rows = BayesianMGMFRM.local_dependence_simulation_grid(;
        profile = planning.planning_profile,
        repetitions = planning.pilot_repetitions,
        base_seed = _ld1b1_int(preflight[:base_seed],
            "protocol pilot base seed"),
        phase = Symbol(_ld1b1_string(preflight[:phase])),
        grid_id = _ld1b1_string(preflight[:grid_id]),
        n_persons = dimensions.n_persons,
        n_testlets = dimensions.n_testlets,
        items_per_testlet = dimensions.items_per_testlet,
        n_raters = dimensions.n_raters,
        n_categories = dimensions.n_categories,
    )
    length(plan_rows) == LD1B1_EXPECTED_PLAN_ROWS ||
        throw(ArgumentError("canonical LD1b1 plan must contain 660 rows"))
    [row.row_index for row in plan_rows] ==
        collect(1:LD1B1_EXPECTED_PLAN_ROWS) || throw(ArgumentError(
        "canonical LD1b1 plan rows are not consecutive"))

    public_preflight =
        BayesianMGMFRM.local_dependence_calibration_pilot_preflight(
            plan_rows; contract = pilot_contract)
    ld1b1_normalized_json(public_preflight) ==
        ld1b1_normalized_json(preflight) || throw(ArgumentError(
        "protocol pilot preflight differs from the public canonical preflight"))

    public_job_rows_sha256 =
        ld1b1_normalized_json_sha256(public_preflight.job_rows)
    artifact_job_rows_sha256 =
        ld1b1_normalized_json_sha256(preflight[:job_rows])
    public_job_rows_sha256 == artifact_job_rows_sha256 ==
        LD1B1_ORDERED_JOB_ROWS_SHA256 || throw(ArgumentError(
        "protocol compact job rows differ from the frozen canonical plan"))

    return (;
        protocol_path = normpath(abspath(protocol_path)),
        protocol,
        protocol_content_hash,
        pilot_contract,
        calibration_contract = pilot_contract.calibration_contract,
        plan_rows = Tuple(plan_rows),
        public_preflight,
        public_contract_sha256,
        artifact_contract_sha256,
        public_job_rows_sha256,
        artifact_job_rows_sha256,
    )
end

function _ld1b1_plan_row(context, row_index::Integer)
    1 <= row_index <= length(context.plan_rows) ||
        throw(ArgumentError("row_index is outside the canonical LD1b1 plan"))
    plan = context.plan_rows[Int(row_index)]
    plan.row_index == row_index ||
        throw(ArgumentError("canonical plan row_index lookup is inconsistent"))
    return plan
end

const _LD1B1_TYPED_SYMBOL_FIELDS = Set((
    :algorithm,
    :caveat,
    :failure_code,
    :family,
    :future_fit_action,
    :maximum_support_status,
    :method,
    :object,
    :profile,
    :role,
    :status,
    :support_status,
))

function _ld1b1_typed_json_value(value, field::Union{Nothing,Symbol} = nothing)
    if field === :data_signature
        return _ld1b1_data_signature(
            value,
            "archived calibration data signature",
        )
    elseif value === nothing || ismissing(value)
        return missing
    elseif value isa NamedTuple || value isa AbstractDict
        names = Tuple(Symbol(String(key)) for key in keys(value))
        values = Tuple(_ld1b1_typed_json_value(
            _ld1b1_field(value, name, "archived calibration member"), name,
        ) for name in names)
        return NamedTuple{names}(values)
    elseif value isa AbstractArray || value isa Tuple
        return Tuple(_ld1b1_typed_json_value(element, field) for element in value)
    elseif value isa AbstractString && field in _LD1B1_TYPED_SYMBOL_FIELDS
        return Symbol(String(value))
    end
    return value
end

function _ld1b1_calibration_template(context, row_index::Integer;
        failure_code::Symbol = :semantic_replay_placeholder)
    plan = _ld1b1_plan_row(context, row_index)
    expected = BayesianMGMFRM.local_dependence_calibration_row(
        plan;
        contract = context.calibration_contract,
        status = :generation_failed,
        failure_code,
    )
    return (; plan, expected)
end

function _ld1b1_linked_failure_code(failure_record, plan,
        status::Symbol)
    status in (:generation_failed, :fit_failed, :diagnostic_failed) ||
        throw(ArgumentError("$status does not use a failure record"))
    role = status === :generation_failed ? :generation_failure_record :
        status === :fit_failed ? :fit_failure_record :
        :diagnostic_failure_record
    stage = status === :generation_failed ? :generation :
        status === :fit_failed ? :fit : :diagnostic
    label = replace(String(role), '_' => '-')
    fields = status === :diagnostic_failed ? (
        :schema, :object, :job_id, :row_index, :scenario_id,
        :replication, :failure_stage, :failure_component, :error_class,
        :failure_recorded,
    ) : (
        :schema, :object, :job_id, :row_index, :scenario_id,
        :replication, :failure_stage, :error_class, :failure_recorded,
    )
    _ld1b1_require_exact_keys(failure_record, fields, label)
    _ld1b1_string(_ld1b1_field(failure_record, :schema, label)) ==
        "bayesianmgmfrm.local_dependence_pilot_failure_record.v1" ||
        throw(ArgumentError("$label has the wrong schema"))
    Symbol(_ld1b1_string(_ld1b1_field(failure_record, :object, label))) ===
        role || throw(ArgumentError("$label has the wrong object"))
    _ld1b1_string(_ld1b1_field(failure_record, :job_id, label)) ==
        _ld1b1_canonical_job_id(plan) ||
        throw(ArgumentError("$label has the wrong job id"))
    _ld1b1_int(_ld1b1_field(failure_record, :row_index, label),
        "$label row index") == plan.row_index &&
        Symbol(_ld1b1_string(_ld1b1_field(
            failure_record, :scenario_id, label))) === plan.scenario_id &&
        _ld1b1_int(_ld1b1_field(failure_record, :replication, label),
            "$label replication") == plan.replication ||
        throw(ArgumentError("$label has the wrong plan identity"))
    Symbol(_ld1b1_string(_ld1b1_field(
        failure_record, :failure_stage, label))) === stage ||
        throw(ArgumentError("$label has the wrong stage"))
    if status === :diagnostic_failed
        component = Symbol(_ld1b1_string(_ld1b1_field(
            failure_record, :failure_component, label)))
        component in (:sampler_quality_gate, :local_dependence_summary) ||
            throw(ArgumentError(
                "$label has an unsupported failure component"))
    end
    _ld1b1_bool(_ld1b1_field(
        failure_record, :failure_recorded, label),
        "$label recorded flag") ||
        throw(ArgumentError("$label is not recorded"))
    error_class = strip(_ld1b1_string(_ld1b1_field(
        failure_record, :error_class, label)))
    isempty(error_class) &&
        throw(ArgumentError("$label error class is empty"))
    failure_code = Symbol(error_class)
    failure_code in ld1b1_nonterminal_artifact_failure_codes() &&
        throw(ArgumentError(
            "$label uses nonterminal artifact-failure code $failure_code"))
    return failure_code
end

const _LD1B1_SIMULATION_PROVENANCE_FIELDS = (
    :status,
    :data_signature,
    :score_signature,
    :observed_score_signature,
    :testlet_design_signature,
    :n_ratings,
    :planning_shape,
    :observed_shape,
    :requested_targets_eligible,
    :future_fit_action,
)
const _LD1B1_DIAGNOSTIC_PROVENANCE_FIELDS = (
    :status,
    :profile,
    :n_draws,
    :data_signature,
    :observed_score_signature,
    :design_signature,
)

function _ld1b1_typed_calibration_member(context, row_index::Integer,
        archived_member; expected_status::Symbol, failure_record = nothing)
    expected_status in (
        :completed,
        :pre_fit_rejected,
        :generation_failed,
        :fit_failed,
        :diagnostic_failed,
    ) || throw(ArgumentError(
        "unexpected calibration terminal status: $expected_status"))
    template = _ld1b1_calibration_template(context, row_index)
    plan = template.plan
    base = template.expected
    archived_status = Symbol(_ld1b1_string(_ld1b1_field(
        archived_member, :status, "archived calibration member")))
    archived_status === expected_status || throw(ArgumentError(
        "archived calibration status differs from the terminal status"))
    failure_code = if expected_status in (
            :generation_failed, :fit_failed, :diagnostic_failed)
        failure_record === nothing && throw(ArgumentError(
            "failed calibration semantic replay lacks its failure record"))
        _ld1b1_linked_failure_code(failure_record, plan, expected_status)
    else
        failure_record === nothing || throw(ArgumentError(
            "nonfailed calibration semantic replay contains a failure record"))
        missing
    end

    archived_simulation_provenance = _ld1b1_field(
        archived_member, :simulation_provenance,
        "archived calibration member")
    if !(archived_simulation_provenance === nothing ||
            ismissing(archived_simulation_provenance))
        _ld1b1_require_exact_keys(
            archived_simulation_provenance,
            _LD1B1_SIMULATION_PROVENANCE_FIELDS,
            "archived calibration simulation provenance",
        )
    end
    simulation_provenance = _ld1b1_typed_json_value(
        archived_simulation_provenance, :simulation_provenance)
    if !ismissing(simulation_provenance)
        archived_shape = getproperty(simulation_provenance, :planning_shape)
        ld1b1_normalized_json(archived_shape) ==
            ld1b1_normalized_json(base.planning_shape) ||
            throw(ArgumentError(
                "archived simulation planning shape differs from the canonical plan"))
        simulation_provenance = merge(
            simulation_provenance,
            (; planning_shape = base.planning_shape),
        )
    end
    archived_diagnostic_provenance = _ld1b1_field(
        archived_member, :diagnostic_provenance,
        "archived calibration member")
    if !(archived_diagnostic_provenance === nothing ||
            ismissing(archived_diagnostic_provenance))
        _ld1b1_require_exact_keys(
            archived_diagnostic_provenance,
            _LD1B1_DIAGNOSTIC_PROVENANCE_FIELDS,
            "archived calibration diagnostic provenance",
        )
    end
    diagnostic_provenance = _ld1b1_typed_json_value(
        archived_diagnostic_provenance, :diagnostic_provenance)
    pair_evidence = _ld1b1_typed_json_value(_ld1b1_field(
        archived_member, :pair_evidence,
        "archived calibration member"), :pair_evidence)
    family_evidence = _ld1b1_typed_json_value(_ld1b1_field(
        archived_member, :family_evidence,
        "archived calibration member"), :family_evidence)
    global_evidence = _ld1b1_typed_json_value(_ld1b1_field(
        archived_member, :global_evidence,
        "archived calibration member"), :global_evidence)
    n_pair_evidence = _ld1b1_int(_ld1b1_field(
        archived_member, :n_pair_evidence,
        "archived calibration member"),
        "archived calibration pair-evidence count")

    typed = merge(base, (;
        status = expected_status,
        failure_code,
        simulation_provenance,
        diagnostic_provenance,
        n_pair_evidence,
        pair_evidence,
        family_evidence,
        global_evidence,
    ))
    ld1b1_normalized_json(typed) == ld1b1_normalized_json(archived_member) ||
        throw(ArgumentError(
            "archived calibration row differs from its canonical typed projection"))
    return (; plan, failure_code, typed)
end

"""
    ld1b1_validate_calibration_member(context, row_index, archived_member;
        expected_status, failure_record = nothing)

Decode one archived calibration row into its canonical Julia types, require an
exact normalized-JSON round trip, and run the public
`local_dependence_calibration_summary` validator against the frozen planning
row. Failed statuses derive their only accepted `failure_code` from the linked
failure record. This performs no fitting or MCMC.
"""
function ld1b1_validate_calibration_member(context, row_index::Integer,
        archived_member; expected_status::Symbol, failure_record = nothing)
    decoded = _ld1b1_typed_calibration_member(
        context,
        row_index,
        archived_member;
        expected_status,
        failure_record,
    )
    summary = BayesianMGMFRM.local_dependence_calibration_summary(
        [decoded.plan],
        [decoded.typed];
        contract = context.calibration_contract,
    )
    summary.n_plan_rows == 1 && summary.n_result_rows == 1 &&
        summary.n_missing_result_rows == 0 || throw(ArgumentError(
        "public calibration semantic replay is incomplete"))
    status_count = only(row.n for row in summary.status_rows
        if row.status === expected_status)
    status_count == 1 || throw(ArgumentError(
        "public calibration semantic replay lost the terminal status"))
    member_json = ld1b1_normalized_json(archived_member)
    return (;
        valid = true,
        plan = decoded.plan,
        failure_code = decoded.failure_code,
        expected = decoded.typed,
        summary,
        member_sha256 = bytes2hex(sha256(codeunits(member_json))),
    )
end

function _ld1b1_optional_probability(value, label::AbstractString)
    (value === nothing || ismissing(value)) && return missing
    number = Float64(value)
    isfinite(number) && 0 <= number <= 1 ||
        throw(ArgumentError("$label must be missing or finite in [0, 1]"))
    return number
end

function _ld1b1_one_family_row(rows, family::Symbol, label::AbstractString)
    matches = [row for row in rows if Symbol(_ld1b1_string(
        _ld1b1_field(row, :family, label))) === family]
    length(matches) == 1 || throw(ArgumentError(
        "$label must contain exactly one row for $family"))
    return only(matches)
end

function _ld1b1_require_canonical_family_rows(rows, families::Tuple,
        label::AbstractString)
    observed = Tuple(sort!(Symbol[
        Symbol(_ld1b1_string(_ld1b1_field(row, :family, label)))
        for row in rows
    ]; by = string))
    expected = Tuple(sort!(collect(families); by = string))
    observed == expected || throw(ArgumentError(
        "$label does not contain the exact canonical family set"))
    return nothing
end

"""
    ld1b1_validate_completed_diagnostic_calibration_link(
        calibration_member, local_dependence_member)

Recompute the completed calibration row's pair, family, and global evidence
from the archived report-only local-dependence summary and its frozen
calibration thresholds. Exact normalized JSON equality is required. This is a
pure semantic replay and performs no fitting, posterior prediction, or MCMC.
"""
function ld1b1_validate_completed_diagnostic_calibration_link(
        calibration_member, local_dependence_member)
    Symbol(_ld1b1_string(_ld1b1_field(
        calibration_member, :status, "calibration member"))) === :completed ||
        throw(ArgumentError(
            "diagnostic-calibration evidence linking requires a completed row"))
    contract = _ld1b1_field(
        calibration_member, :contract, "calibration member")
    thresholds = _ld1b1_field(
        contract, :candidate_thresholds, "calibration contract")
    pair_raw_alpha = Float64(_ld1b1_field(
        thresholds, :pair_raw_alpha, "calibration thresholds"))
    pair_bh_alpha = Float64(_ld1b1_field(
        thresholds, :pair_bh_alpha, "calibration thresholds"))
    family_alpha = Float64(_ld1b1_field(
        thresholds, :family_maximum_alpha, "calibration thresholds"))
    global_alpha = Float64(_ld1b1_field(
        thresholds, :global_maximum_alpha, "calibration thresholds"))
    all(0 < value < 1 for value in (
        pair_raw_alpha, pair_bh_alpha, family_alpha, global_alpha)) ||
        throw(ArgumentError("calibration thresholds must lie in (0, 1)"))

    local_diagnostic_provenance = (;
        status = Symbol(_ld1b1_string(_ld1b1_field(
            local_dependence_member, :status,
            "local-dependence member"))),
        profile = Symbol(_ld1b1_string(_ld1b1_field(
            local_dependence_member, :profile,
            "local-dependence member"))),
        n_draws = _ld1b1_int(_ld1b1_field(
            local_dependence_member, :n_draws,
            "local-dependence member"),
            "local-dependence draw count"),
        data_signature = _ld1b1_data_signature(_ld1b1_field(
            local_dependence_member, :data_signature,
            "local-dependence member"),
            "local-dependence data signature"),
        observed_score_signature = _ld1b1_field(
            local_dependence_member, :observed_score_signature,
            "local-dependence member"),
        design_signature = _ld1b1_field(
            local_dependence_member, :design_signature,
            "local-dependence member"),
    )
    archived_diagnostic_provenance = _ld1b1_field(
        calibration_member, :diagnostic_provenance, "calibration member")
    archived_data_signature = _ld1b1_data_signature(_ld1b1_field(
        archived_diagnostic_provenance,
        :data_signature,
        "calibration diagnostic provenance",
    ), "calibration diagnostic data signature")
    archived_data_signature == local_diagnostic_provenance.data_signature ||
        throw(ArgumentError(
            "calibration diagnostic data signature differs from the linked local-dependence summary"))
    ld1b1_normalized_json(archived_diagnostic_provenance) ==
        ld1b1_normalized_json(local_diagnostic_provenance) ||
        throw(ArgumentError(
            "calibration diagnostic provenance differs from the linked local-dependence summary"))

    local_pairs = _ld1b1_field(
        local_dependence_member, :pair_rows, "local-dependence member")
    pair_evidence = Tuple((function ()
        family = Symbol(_ld1b1_string(_ld1b1_field(
            pair, :family, "local-dependence pair row")))
        support_status = Symbol(_ld1b1_string(_ld1b1_field(
            pair, :status, "local-dependence pair row")))
        raw = _ld1b1_optional_probability(_ld1b1_field(
            pair, :posterior_predictive_tail_fraction,
            "local-dependence pair row"),
            "pair posterior-predictive tail fraction")
        bh = _ld1b1_optional_probability(_ld1b1_field(
            pair, :bh_adjusted_tail_fraction,
            "local-dependence pair row"),
            "pair BH-adjusted tail fraction")
        eligible = support_status === :eligible_report_only && !ismissing(raw)
        eligible && ismissing(bh) && throw(ArgumentError(
            "eligible local-dependence pair lacks its BH-adjusted tail"))
        return (;
            family,
            testlet_id = _ld1b1_field(
                pair, :testlet_id, "local-dependence pair row"),
            left = _ld1b1_field(
                pair, :left, "local-dependence pair row"),
            right = _ld1b1_field(
                pair, :right, "local-dependence pair row"),
            support_status,
            eligible,
            posterior_predictive_tail_fraction = raw,
            bh_adjusted_tail_fraction = bh,
            candidate_raw_declared = eligible ?
                raw <= pair_raw_alpha : missing,
            candidate_bh_declared = eligible ?
                bh <= pair_bh_alpha : missing,
        )
    end)() for pair in local_pairs)

    families = (
        :single_rating_item_q3,
        :within_rater_item_q3,
        :rater_on_shared_response_criterion,
    )
    support_rows = _ld1b1_field(
        local_dependence_member, :family_rows,
        "local-dependence member")
    maximum_rows = _ld1b1_field(
        local_dependence_member, :family_max_rows,
        "local-dependence member")
    _ld1b1_require_canonical_family_rows(
        support_rows, families, "local-dependence family rows")
    _ld1b1_require_canonical_family_rows(
        maximum_rows, families, "local-dependence family-maximum rows")
    family_evidence = Tuple((function ()
        support = _ld1b1_one_family_row(
            support_rows, family, "local-dependence family rows")
        maximum = _ld1b1_one_family_row(
            maximum_rows, family, "local-dependence family-maximum rows")
        support_status = Symbol(_ld1b1_string(_ld1b1_field(
            support, :status, "local-dependence family row")))
        maximum_support_status = Symbol(_ld1b1_string(_ld1b1_field(
            maximum, :support_status,
            "local-dependence family-maximum row")))
        tail = _ld1b1_optional_probability(_ld1b1_field(
            maximum, :posterior_predictive_tail_fraction,
            "local-dependence family-maximum row"),
            "family maximum tail fraction")
        all_pairs = [row for row in pair_evidence if row.family === family]
        eligible_pairs = [row for row in all_pairs if row.eligible]
        applicable = support_status !== :not_applicable
        evaluable = applicable && !ismissing(tail)
        return (;
            family,
            support_status,
            applicable,
            n_pair_rows = length(all_pairs),
            n_eligible_pairs = length(eligible_pairs),
            n_raw_declared = count(
                row -> row.candidate_raw_declared === true, eligible_pairs),
            n_bh_declared = count(
                row -> row.candidate_bh_declared === true, eligible_pairs),
            any_raw_declared = isempty(eligible_pairs) ? missing :
                any(row -> row.candidate_raw_declared === true,
                    eligible_pairs),
            any_bh_declared = isempty(eligible_pairs) ? missing :
                any(row -> row.candidate_bh_declared === true,
                    eligible_pairs),
            maximum_support_status,
            maximum_tail_fraction = tail,
            family_evaluable = evaluable,
            candidate_family_declared = evaluable ?
                tail <= family_alpha : missing,
        )
    end)() for family in families)

    local_global = _ld1b1_field(
        local_dependence_member, :global_evidence,
        "local-dependence member")
    global_tail = _ld1b1_optional_probability(_ld1b1_field(
        local_global, :posterior_predictive_tail_fraction,
        "local-dependence global evidence"),
        "global maximum tail fraction")
    global_evaluable = !ismissing(global_tail)
    global_evidence = (;
        support_status = Symbol(_ld1b1_string(_ld1b1_field(
            local_global, :support_status,
            "local-dependence global evidence"))),
        n_overall_supported_pairs = _ld1b1_int(_ld1b1_field(
            local_global, :n_overall_supported_pairs,
            "local-dependence global evidence"),
            "global supported-pair count"),
        tail_fraction = global_tail,
        evaluable = global_evaluable,
        candidate_global_declared = global_evaluable ?
            global_tail <= global_alpha : missing,
    )

    comparisons = (
        (:pair_evidence, pair_evidence),
        (:family_evidence, family_evidence),
        (:global_evidence, global_evidence),
    )
    for (field, expected) in comparisons
        observed = _ld1b1_field(
            calibration_member, field, "calibration member")
        ld1b1_normalized_json(observed) == ld1b1_normalized_json(expected) ||
            throw(ArgumentError(
                "calibration $field differs from the linked local-dependence summary"))
    end
    _ld1b1_int(_ld1b1_field(
        calibration_member, :n_pair_evidence, "calibration member"),
        "calibration pair-evidence count") == length(pair_evidence) ||
        throw(ArgumentError(
            "calibration pair-evidence count differs from the linked summary"))
    return (;
        valid = true,
        n_pair_evidence = length(pair_evidence),
        pair_evidence_sha256 = ld1b1_normalized_json_sha256(pair_evidence),
        family_evidence_sha256 =
            ld1b1_normalized_json_sha256(family_evidence),
        global_evidence_sha256 =
            ld1b1_normalized_json_sha256(global_evidence),
    )
end

"""
    ld1b1_canonical_generation_failed_row(context, row_index;
        failure_record)

Construct and publicly validate the one canonical `generation_failed`
calibration row linked to `failure_record`. No simulation or model execution is
performed.
"""
function ld1b1_canonical_generation_failed_row(context,
        row_index::Integer; failure_record)
    plan = _ld1b1_plan_row(context, row_index)
    failure_code =
        _ld1b1_linked_failure_code(failure_record, plan, :generation_failed)
    expected = BayesianMGMFRM.local_dependence_calibration_row(
        plan;
        contract = context.calibration_contract,
        status = :generation_failed,
        failure_code,
    )
    summary = BayesianMGMFRM.local_dependence_calibration_summary(
        [plan], [expected]; contract = context.calibration_contract)
    summary.n_plan_rows == 1 && summary.n_result_rows == 1 &&
        summary.n_missing_result_rows == 0 || throw(ArgumentError(
        "public generation-failure calibration validation is incomplete"))
    failure_count = only(row.n for row in summary.status_rows
        if row.status === :generation_failed)
    failure_count == 1 || throw(ArgumentError(
        "public calibration summary lost the generation failure"))
    return (; plan, failure_code, expected, summary)
end

"""
    ld1b1_validate_generation_failed_member(context, row_index,
        archived_member; failure_record)

Require an archived `generation_failed` calibration member to equal the
canonical public row exactly after normalized JSON projection. The linked
failure record supplies the only accepted `failure_code`.
"""
function ld1b1_validate_generation_failed_member(context,
        row_index::Integer, archived_member; failure_record)
    return ld1b1_validate_calibration_member(
        context,
        row_index,
        archived_member;
        expected_status = :generation_failed,
        failure_record,
    )
end

end # module LocalDependencePilotCalibrationSemantics
