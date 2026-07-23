module ScientificPayloadDigest

using SHA: sha256

include(joinpath(@__DIR__, "local_json.jl"))

export canonical_json_bytes,
    canonical_json_sha256,
    reference_integrity_status,
    recorded_scientific_payload_sha256,
    ScientificPayloadSchemaContract,
    scientific_payload_sha256,
    strict_archive_sha_enabled,
    validate_scientific_payload_schema,
    verify_scientific_payload_sha256

const SCIENTIFIC_PAYLOAD_CANONICALIZATION =
    :local_json_sorted_compact_v1
const _LOWERCASE_SHA256 = r"^[0-9a-f]{64}$"

function _schema_field_name(field, label::AbstractString)
    field isa Symbol || field isa AbstractString || throw(ArgumentError(
        "$label entries must be strings or symbols; got $(typeof(field))",
    ))
    name = String(field)
    isempty(name) && throw(ArgumentError("$label entries cannot be empty"))
    isvalid(name) || throw(ArgumentError(
        "$label entries must contain valid UTF-8",
    ))
    return name
end

"""
    ScientificPayloadSchemaContract(schema;
        required_fields, optional_fields = ())

Describe the exact top-level allow-list for one scientific payload schema.
`required_fields` must explicitly include `:schema` plus at least one
scientific field. Fields outside the required/optional union are rejected.

This contract deliberately covers the materialized top-level projection. A
generator remains responsible for constructing and validating any nested
schema objects before hashing them.
"""
struct ScientificPayloadSchemaContract
    schema::String
    required_fields::Tuple
    optional_fields::Tuple

    function ScientificPayloadSchemaContract(
            schema::AbstractString,
            required_fields::Tuple,
            optional_fields::Tuple)
        checked_schema = String(schema)
        isempty(checked_schema) &&
            throw(ArgumentError("scientific payload schema cannot be empty"))
        isvalid(checked_schema) || throw(ArgumentError(
            "scientific payload schema must contain valid UTF-8",
        ))
        required = Tuple(
            _schema_field_name(field, "required_fields")
            for field in required_fields
        )
        optional = Tuple(
            _schema_field_name(field, "optional_fields")
            for field in optional_fields
        )
        length(unique(required)) == length(required) || throw(ArgumentError(
            "required_fields contains a duplicate canonical field",
        ))
        length(unique(optional)) == length(optional) || throw(ArgumentError(
            "optional_fields contains a duplicate canonical field",
        ))
        isempty(intersect(Set(required), Set(optional))) || throw(ArgumentError(
            "required_fields and optional_fields must be disjoint",
        ))
        "schema" in required || throw(ArgumentError(
            "required_fields must explicitly include :schema",
        ))
        length(required) >= 2 || throw(ArgumentError(
            "a scientific payload schema must require at least one material " *
            "field in addition to :schema",
        ))
        return new(checked_schema, required, optional)
    end
end

function ScientificPayloadSchemaContract(
        schema::AbstractString;
        required_fields,
        optional_fields = ())
    return ScientificPayloadSchemaContract(
        schema,
        Tuple(required_fields),
        Tuple(optional_fields),
    )
end

function _scientific_payload_key(key, path::AbstractString)
    key isa Symbol || key isa AbstractString || throw(ArgumentError(
        "scientific payload object keys must be strings or symbols at $path; " *
        "got $(typeof(key))",
    ))
    canonical = String(key)
    isvalid(canonical) || throw(ArgumentError(
        "scientific payload object keys must contain valid UTF-8 at $path",
    ))
    return canonical
end

function _validate_scientific_payload(value, path::AbstractString = "\$")
    value === missing && throw(ArgumentError(
        "scientific payload cannot contain `missing` at $path; " *
        "normalize an intentional JSON null to `nothing`",
    ))
    if value === nothing || value isa Bool || value isa Integer
        return nothing
    elseif value isa Symbol || value isa AbstractString
        isvalid(String(value)) || throw(ArgumentError(
            "scientific payload strings must contain valid UTF-8 at $path",
        ))
        return nothing
    elseif value isa Float64
        isfinite(value) || throw(ArgumentError(
            "scientific payload contains a non-finite number at $path",
        ))
        return nothing
    elseif value isa AbstractFloat
        throw(ArgumentError(
            "scientific payload floating-point values must be normalized " *
            "to Float64 at $path; got $(typeof(value))",
        ))
    elseif value isa NamedTuple || value isa AbstractDict
        seen = Set{String}()
        for (key, item) in pairs(value)
            canonical_key = _scientific_payload_key(key, path)
            canonical_key in seen && throw(ArgumentError(
                "scientific payload contains colliding canonical key " *
                "$(repr(canonical_key)) at $path",
            ))
            push!(seen, canonical_key)
            _validate_scientific_payload(
                item,
                path * "." * canonical_key,
            )
        end
        return nothing
    elseif value isa Tuple
        for (index, item) in enumerate(value)
            _validate_scientific_payload(item, "$path[$index]")
        end
        return nothing
    elseif value isa AbstractArray
        ndims(value) == 1 || throw(ArgumentError(
            "scientific payload arrays must be one-dimensional at $path; " *
            "project matrices explicitly as ordered row arrays",
        ))
        for (index, item) in enumerate(value)
            _validate_scientific_payload(item, "$path[$index]")
        end
        return nothing
    end
    throw(ArgumentError(
        "scientific payload contains unsupported $(typeof(value)) at $path; " *
        "normalize it to JSON scalar, object, or ordered one-dimensional array",
    ))
end

"""
    canonical_json_bytes(payload)

Return the UTF-8 bytes of the repository's sorted, compact JSON
canonicalization after applying the strict scientific-payload checks. Object
keys are order-independent; array order is significant. Non-finite numbers,
`missing`, multidimensional arrays, unsupported values, and keys that collide
after string conversion are rejected.
"""
function canonical_json_bytes(payload)
    _validate_scientific_payload(payload)
    io = IOBuffer()
    write_canonical_json(io, payload)
    return take!(io)
end

canonical_json_sha256(payload) =
    bytes2hex(sha256(canonical_json_bytes(payload)))

"""
    scientific_payload_sha256(payload)

Hash an explicit, schema-specific scientific projection. This function does
not remove fields by name: the generator must construct the projection it
intends to protect before calling it.
"""
scientific_payload_sha256(payload) = canonical_json_sha256(payload)

function _object_entries(value, label::AbstractString)
    value isa NamedTuple || value isa AbstractDict || throw(ArgumentError(
        "$label must be a top-level object",
    ))
    entries = Dict{String,Any}()
    for (key, item) in pairs(value)
        canonical_key = _scientific_payload_key(key, label)
        haskey(entries, canonical_key) && throw(ArgumentError(
            "$label contains multiple physical keys that canonicalize to " *
            repr(canonical_key),
        ))
        entries[canonical_key] = item
    end
    return entries
end

"""
    validate_scientific_payload_schema(payload, contract)

Validate a materialized scientific projection against its expected schema and
exact top-level field allow-list. Return `payload` after validation.
"""
function validate_scientific_payload_schema(
        payload,
        contract::ScientificPayloadSchemaContract)
    _validate_scientific_payload(payload)
    entries = _object_entries(payload, "scientific_payload")
    required = Set(contract.required_fields)
    allowed = union(required, Set(contract.optional_fields))
    missing_fields = sort!(collect(setdiff(required, Set(keys(entries)))))
    isempty(missing_fields) || throw(ArgumentError(
        "scientific_payload is missing required fields: " *
        join(missing_fields, ", "),
    ))
    unexpected_fields = sort!(collect(setdiff(Set(keys(entries)), allowed)))
    isempty(unexpected_fields) || throw(ArgumentError(
        "scientific_payload contains fields outside the schema allow-list: " *
        join(unexpected_fields, ", "),
    ))
    recorded_schema = entries["schema"]
    recorded_schema isa AbstractString || throw(ArgumentError(
        "scientific_payload.schema must be a string",
    ))
    String(recorded_schema) == contract.schema || throw(ArgumentError(
        "scientific_payload schema mismatch: expected " *
        repr(contract.schema) * ", got " * repr(String(recorded_schema)),
    ))
    return payload
end

function scientific_payload_sha256(
        payload,
        contract::ScientificPayloadSchemaContract)
    validate_scientific_payload_schema(payload, contract)
    return canonical_json_sha256(payload)
end

function _checked_sha256(value, label::AbstractString)
    value isa AbstractString || throw(ArgumentError(
        "$label must be a lowercase 64-character SHA-256 string",
    ))
    digest = String(value)
    occursin(_LOWERCASE_SHA256, digest) || throw(ArgumentError(
        "$label must be a lowercase 64-character SHA-256 string",
    ))
    return digest
end

"""
    verify_scientific_payload_sha256(payload, expected)

Recompute an explicit scientific payload digest and throw when it does not
match the recorded lowercase SHA-256 value. Return the verified digest.
"""
function verify_scientific_payload_sha256(payload, expected)
    checked = _checked_sha256(expected, "scientific_payload_sha256")
    actual = scientific_payload_sha256(payload)
    actual == checked || throw(ArgumentError(
        "scientific payload SHA-256 mismatch: expected $checked, got $actual",
    ))
    return actual
end

function verify_scientific_payload_sha256(
        payload,
        expected,
        contract::ScientificPayloadSchemaContract)
    validate_scientific_payload_schema(payload, contract)
    return verify_scientific_payload_sha256(payload, expected)
end

function _artifact_field(artifact, field::Symbol)
    entries = _object_entries(artifact, "artifact")
    string_field = String(field)
    return haskey(entries, string_field), get(entries, string_field, nothing)
end

"""
    recorded_scientific_payload_sha256(artifact;
        allow_legacy = false, schema_contract = nothing)

Verify the paired top-level `scientific_payload` and
`scientific_payload_sha256` fields and return the digest. Both fields absent
are accepted only when `allow_legacy = true`, in which case `missing` is
returned and must not be treated as verified equivalence. A partial pair,
malformed digest, schema-contract violation, or mismatch always fails. A
present pair requires an explicit [`ScientificPayloadSchemaContract`](@ref),
so digest self-consistency alone is never treated as a semantic gate.
"""
function recorded_scientific_payload_sha256(
        artifact;
        allow_legacy::Bool = false,
        schema_contract = nothing)
    has_payload, payload = _artifact_field(artifact, :scientific_payload)
    has_digest, digest =
        _artifact_field(artifact, :scientific_payload_sha256)
    if !has_payload && !has_digest
        allow_legacy && return missing
        throw(ArgumentError(
            "artifact does not record a scientific payload digest",
        ))
    end
    has_payload == has_digest || throw(ArgumentError(
        "artifact must record scientific_payload and " *
        "scientific_payload_sha256 together",
    ))
    schema_contract isa ScientificPayloadSchemaContract ||
        throw(ArgumentError(
            "a present scientific payload requires an explicit " *
            "ScientificPayloadSchemaContract",
        ))
    return verify_scientific_payload_sha256(
        payload,
        digest,
        schema_contract,
    )
end

"""
    strict_archive_sha_enabled()

Return whether exact archive byte matching was explicitly requested through
`BAYESIANMGMFRM_STRICT_ARCHIVE_SHA`. Ordinary unit tests may classify code and
documentation drift; release reproduction runs should enable strict mode.
"""
function strict_archive_sha_enabled()
    value = lowercase(strip(get(
        ENV,
        "BAYESIANMGMFRM_STRICT_ARCHIVE_SHA",
        "false",
    )))
    value in ("1", "true", "yes", "on") && return true
    value in ("", "0", "false", "no", "off") && return false
    throw(ArgumentError(
        "BAYESIANMGMFRM_STRICT_ARCHIVE_SHA must be one of " *
        "1/true/yes/on or 0/false/no/off; got $(repr(value))",
    ))
end

"""
    reference_integrity_status(recorded, current;
        reference_kind, strict = strict_archive_sha_enabled())

Classify an exact-file SHA comparison without claiming that provenance drift
is scientific equivalence. Only `reference_kind = :code_doc` may remain
loadable outside strict archive mode. Raw data, immutable snapshots, receipts,
and generated artifacts remain exact-SHA gates.
"""
function reference_integrity_status(
        recorded,
        current;
        reference_kind::Symbol,
        strict::Bool = strict_archive_sha_enabled())
    recorded_sha256 = _checked_sha256(recorded, "recorded file SHA-256")
    current_sha256 = _checked_sha256(current, "current file SHA-256")
    exact = recorded_sha256 == current_sha256
    if exact
        return (;
            status = :exact_file_match,
            provenance_policy_accepted = true,
            exact_file_sha256_verified = true,
            scientific_equivalence_verified = false,
            archive_refresh_required = false,
            reference_kind,
            strict,
            recorded_sha256,
            current_sha256,
        )
    end
    code_doc_drift = reference_kind === :code_doc
    return (;
        status = code_doc_drift ? :provenance_drift : :integrity_mismatch,
        provenance_policy_accepted = code_doc_drift && !strict,
        exact_file_sha256_verified = false,
        scientific_equivalence_verified = false,
        archive_refresh_required = true,
        reference_kind,
        strict,
        recorded_sha256,
        current_sha256,
    )
end

end
