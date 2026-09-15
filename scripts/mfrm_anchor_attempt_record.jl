module MFRMAnchorAttemptRecord

import BayesianMGMFRM
using Random, Serialization, SHA

include(joinpath(@__DIR__, "local_dependence_pilot_attempt_archive.jl"))
const Archive = LocalDependencePilotAttemptArchive
const publish_record = Archive.ld1b_atomic_publish_json_create_new

struct FitObservationError <: Exception
    stage::Symbol
    cause::CapturedException
    returned_fit
end

function Base.showerror(io::IO, err::FitObservationError)
    print(io, "fit observation failed at ", err.stage, ": ")
    showerror(io, err.cause)
end

"""
    observe_fit(invoke; record_event)

Run one audited, synchronous `invoke(on_enter)` closure which directly calls
minimal `fit(design; _on_enter = on_enter, ...)` and returns its result unchanged.
The closure must not catch errors or call another fit. `record_event(stage)`
must throw on recording failure; it receives `:fit_entered` inside the fit body
before validation and `:fit_returned` only after the call returns.

Call exceptions propagate unchanged. Recording errors are `FitObservationError`;
after return they retain the actual result in `returned_fit`, without hashing,
scoring, or retrying it. A thrown recorder may already have published its record:
use `recover_record`, not a refit. Missing records still mean unknown after a
process interruption. The caller must first retain the input declaration and
bind both records to it. This helper does not audit that declaration or closure,
freeze an event schema, or supply lifecycle counts.
"""
function observe_fit(invoke; record_event)
    # ponytail: one trusted direct call; no executor, callback interception,
    # task-local hooks, or retry policy until a reviewed workflow needs them.
    entered = false
    on_enter = () -> begin
        try
            entered && throw(ArgumentError("only one fit entry is allowed"))
            record_event(:fit_entered)
            entered = true
        catch err
            throw(FitObservationError(:fit_entered,
                CapturedException(err, catch_backtrace()), nothing))
        end
        return nothing
    end
    result = invoke(on_enter) # Do not catch fitting/dispatch/input exceptions here.
    try
        entered || throw(ArgumentError("call returned without a recorded fit entry"))
        record_event(:fit_returned)
    catch err
        throw(FitObservationError(:fit_returned,
            CapturedException(err, catch_backtrace()), result))
    end
    return result
end

function _prepare_fit_inputs(design::BayesianMGMFRM.FacetDesign, options::NamedTuple)
    required = (:prior, :backend, :ndraws, :warmup, :chains, :step_size, :init,
        :rng, :seed, :target_accept, :max_depth, :max_energy_error, :metric,
        :ad_backend, :init_jitter, :progress, :cmdstan_path, :cmdstan_cache_dir)
    Set(keys(options)) == Set(required) || throw(ArgumentError(
        "fit input options must explicitly supply every minimal-fit keyword except _on_enter"))
    options.prior isa BayesianMGMFRM.MFRMPrior && options.rng isa AbstractRNG ||
        throw(ArgumentError("fit inputs require MFRMPrior and AbstractRNG"))
    options.backend in (:julia, :advancedhmc, :turing, :cmdstan) &&
        all(k -> options[k] isa Int, (:ndraws, :warmup, :chains, :max_depth)) &&
        options.metric isa Symbol && options.ad_backend isa Symbol &&
        options.progress isa Bool && all(k -> options[k] === nothing ||
            options[k] isa AbstractString, (:cmdstan_path, :cmdstan_cache_dir)) ||
        throw(ArgumentError("invalid fit input option types or backend"))
    real_keys = (:step_size, :target_accept, :max_energy_error, :init_jitter)
    all(k -> options[k] isa Real && !(options[k] isa Bool) &&
        isfinite(Float64(options[k])), real_keys) || throw(ArgumentError(
        "fit input real-valued options must be finite and representable as Float64"))
    reals = NamedTuple{real_keys}(Tuple(Float64(options[k]) for k in real_keys))
    snapshot = BayesianMGMFRM._validated_design_snapshot(design, "anchor fit inputs")
    snapshot.spec.family === :mfrm && snapshot.spec.estimation_status === :fit_supported ||
        throw(ArgumentError("fit input binding supports only the minimal MFRM design"))
    initial = BayesianMGMFRM._fit_initial_params(snapshot, options.init)
    initial isa Vector{Float64} || throw(ArgumentError(
        "fit input initialization must normalize to a one-dimensional vector"))
    # ponytail: own MersenneTwister state only; add another unseeded RNG after
    # its copy/serialization/replay contract is checked, never copy TaskLocalRNG.
    options.seed isa Bool && throw(ArgumentError("fit input seed must not be Boolean"))
    if options.seed === nothing
        options.rng isa MersenneTwister || throw(ArgumentError(
            "unseeded fit input binding requires an owned MersenneTwister snapshot"))
        owned_rng, seed = copy(options.rng), nothing
        io = IOBuffer()
        serialize(io, owned_rng)
        state = take!(io)
        rng_record = (; mode = :owned_state, algorithm = :MersenneTwister,
            seed, format = :julia_serialization, state, sha256 = bytes2hex(sha256(state)))
    else
        owned_rng, control = BayesianMGMFRM._fit_rng(options.rng, options.seed)
        seed = control.seed
        rng_record = (; mode = :explicit_seed, algorithm = control.algorithm, seed)
    end
    owned = merge(deepcopy(Base.structdiff(options, (; rng = nothing))), reals,
        (; rng = owned_rng, seed, init = options.init === nothing ? nothing : initial))
    fit_input = Archive._ld1b_object((;
        schema = "bayesianmgmfrm.anchor_fit_input.v2",
        julia_version = string(VERSION), architecture = string(Sys.ARCH),
        word_size = Sys.WORD_SIZE,
        design = BayesianMGMFRM._design_identity_payload(snapshot),
        # Keep the canonical SHA and payload, not the redundant UInt64 legacy
        # signature that untyped JSON readers can round through Float64.
        design_identity = Base.structdiff(BayesianMGMFRM.design_identity(snapshot),
            (; data_signature = nothing)),
        prior = BayesianMGMFRM._prior_cache_record(owned.prior),
        initialization = (; policy = options.init === nothing ? :default_zero : :provided,
            parameter_names = snapshot.parameter_names, values = initial),
        rng = rng_record,
        settings = Base.structdiff(owned, (; prior = nothing, init = nothing,
            rng = nothing, seed = nothing))), "fit input binding")
    return (; design = snapshot, options = owned, fit_input)
end

"""
    fit_input_record(design; options)

Snapshot the labelled minimal design, prior, all explicit fit options, ordered
initial values, and either an explicit seed or a copied MersenneTwister state.
This does not fit, consume the caller's RNG, publish, or accept a study policy.
Retain this native JSON object as `fit_input` in the caller's content-hashed
pre-call declaration. RNG serialization is scoped to the recorded Julia/version
platform, not a portable replay format; no serialized input is deserialized.
"""
fit_input_record(design; options::NamedTuple) = _prepare_fit_inputs(design, options).fit_input

function _record_snapshot(path::AbstractString, boundary::AbstractString)
    all(p -> isabspath(p) && normpath(p) == p, (path, boundary)) ||
        throw(ArgumentError("record paths must be normalized and absolute"))
    Archive._ld1b_require_directory(boundary, boundary, "record boundary")
    saved = Archive._ld1b_read_json_snapshot(path, boundary, "retained record")
    content_hash = Archive.ld1b_verify_archive_content_hash(saved.parsed)
    return (; saved, reference = (; path = String(path), content_hash, file_sha256 = saved.sha256))
end

function _verified_record(path, expected, boundary; semantic_validator)
    expected = Archive._ld1b_object(expected, "expected record")
    Archive.ld1b_verify_archive_content_hash(expected)
    semantic_validator(deepcopy(expected))
    record = _record_snapshot(path, boundary)
    record.saved.bytes == Archive._ld1b_encode_json_bytes(expected) || throw(ArgumentError(
        "published record differs from the separately retained expected bytes"))
    return (; data = expected, record.reference)
end

function _pinned_record(reference, boundary)
    ref = Archive._ld1b_exact_keys(reference, (:path, :content_hash, :file_sha256), "record reference")
    record = _record_snapshot(Archive._ld1b_string(ref["path"], "record path"), boundary)
    Archive._ld1b_json_native(record.reference) == ref || throw(ArgumentError(
        "record differs from its retained content/file binding"))
    return record.saved.parsed
end

"""
    observe_declared_fit(design; options, path, expected, boundary,
        semantic_validator, record_event)

Compare owned input snapshots with the separately retained declaration and its
already-published, single-link JSON file before invoking minimal fit exactly
once. Preflight is read only; absent/conflicting/unreconciled files cannot start
a fit. The validator checks the caller's attempt/truth/source/environment scope
and must throw on rejection. No such scientific schema is defaulted here.

`record_event(stage, binding)` receives the verified declaration content/file
hashes for both observations. It must preserve that binding and not modify the
retained declaration; it never receives the private call inputs. Call and
recording exception semantics are those of `observe_fit`. This is not an executor, restart guard,
scorer, resource authorization, or concurrent-writer protocol.
"""
function observe_declared_fit(design; options::NamedTuple, path::AbstractString,
        expected, boundary::AbstractString, semantic_validator, record_event)
    actual = _prepare_fit_inputs(design, options)
    verified = _verified_record(path, expected, boundary; semantic_validator)
    haskey(verified.data, "fit_input") && Archive._ld1b_encode_json_bytes(verified.data["fit_input"]) ==
        Archive._ld1b_encode_json_bytes(actual.fit_input) || throw(ArgumentError(
            "actual fit inputs differ from the retained pre-call declaration"))
    binding = (; input_content_hash = verified.reference.content_hash,
        input_file_sha256 = verified.reference.file_sha256)
    return observe_fit(; record_event = stage -> record_event(stage, binding)) do on_enter
        BayesianMGMFRM.fit(actual.design; actual.options..., _on_enter = on_enter)
    end
end

"""Construct the minimal entry/return transport record; not evidence that a call ran."""
function fit_event_record(stage::Symbol, binding)
    stage in (:fit_entered, :fit_returned) || throw(ArgumentError("unsupported fit event stage"))
    input = Archive._ld1b_exact_keys(binding, (:input_content_hash, :input_file_sha256), "input binding")
    all(value -> value isa AbstractString && occursin(r"\A[0-9a-f]{64}\z", value), values(input)) ||
        throw(ArgumentError("input digests must be lowercase 64-hex"))
    return Archive.ld1b_archive_with_content_hash((;
        schema = "bayesianmgmfrm.anchor_fit_event.v1", stage, input_binding = input))
end

function _check_scoring_plan(declaration, reference::NamedTuple)
    any(k -> haskey(reference, k), (:fit_sha256, :fit_provenance)) &&
        throw(ArgumentError("pre-call scoring reference must not contain derived fit fields"))
    BayesianMGMFRM._mfrm_anchor_primary_attempts([reference], NamedTuple[])
    haskey(reference, :attempt) && reference.attempt isa Integer &&
        !(reference.attempt isa Bool) && reference.attempt > 0 ||
        throw(ArgumentError("scoring reference requires a positive attempt number"))
    all(k -> get(declaration, String(k), nothing) == reference[k],
        (:dataset_id, :heldout_id, :method, :attempt)) &&
        get(declaration, "scoring_plan_sha256", nothing) == BayesianMGMFRM._cache_hash(reference) ||
        throw(ArgumentError("scoring plan or attempt differs from the pre-call declaration"))
    return nothing
end

"""
    check_source_environment(declaration, reference)

Compose this read-only check into the pre-entry `semantic_validator`. The
pre-call scoring reference must bind `project_environment = (active_project =
absolute_path, manifest = absolute_path)`, with both paths in its independently
retained `required_source_paths` and `source_files`. Check the bound plan, every
supplied file digest (including extras), and the actual active/resolved paths
and digests. Missing evidence rejects; no environment is inferred or repaired.

This checks current files/resolution, not dependency validity, loaded methods,
native binaries, or scientific readiness. It does not collect optional R/Git/
CmdStan metadata, publish a declaration, or install itself in existing callers.
"""
function check_source_environment(declaration, reference::NamedTuple)
    reference = deepcopy(reference)
    _check_scoring_plan(Archive._ld1b_object(declaration, "input declaration"), reference)
    all(k -> haskey(reference, k), (:source_files, :project_environment)) ||
        throw(ArgumentError("source/environment declaration is missing required fields"))
    required = BayesianMGMFRM._mfrm_anchor_required_sources(reference)
    required === nothing && throw(ArgumentError("pre-entry source coverage must be declared"))
    environment = Archive._ld1b_exact_keys(reference.project_environment,
        (:active_project, :manifest), "project environment")
    all(path -> path in required, values(environment)) || throw(ArgumentError(
        "Project and Manifest paths must be in the independently declared source roster"))
    for (path, digest) in reference.source_files
        path isa AbstractString && isabspath(path) && normpath(path) == path &&
            digest isa AbstractString && occursin(r"\A[0-9a-f]{64}\z", digest) ||
            throw(ArgumentError("source references require normalized absolute paths and lowercase 64-hex digests"))
        BayesianMGMFRM._evidence_file_sha256(path) == digest || throw(ArgumentError(
            "source file differs from its pre-call declaration"))
    end
    # ponytail: trusted files stable during this synchronous check/call; a
    # reviewed immutable launch is needed for loaded-code or concurrent-change claims.
    issues = Any[]
    actual = BayesianMGMFRM._evidence_project_hashes(; include_paths = true, issues)
    isempty(issues) && all(actual[key] == path &&
        actual[key * "_sha256"] == reference.source_files[path]
        for (key, path) in environment) || throw(ArgumentError(
            "active Project or resolved Manifest differs from its pre-call declaration"))
    return nothing
end

function _link_returned_fit(fit, base_reference, provenance)
    try
        fit_sha256 = BayesianMGMFRM._mfrm_anchor_fit_hash(fit)
        reference = merge(base_reference, (; fit_sha256, fit_provenance = provenance))
        link = Archive.ld1b_archive_with_content_hash((;
            schema = "bayesianmgmfrm.anchor_fit_return_link.v1", fit_sha256,
            reference_sha256 = BayesianMGMFRM._cache_hash(reference), fit_provenance = provenance))
        return (; fit, reference, link)
    catch err
        throw(FitObservationError(:fit_linked, CapturedException(err, catch_backtrace()), fit))
    end
end

"""
    observe_linked_fit(design; reference, options, path, expected, boundary,
        semantic_validator, record_event)

Use the declared-input bridge once, then link its actual returned object to the
pre-call scoring plan and published observations. The outer declaration must
contain dataset_id/heldout_id/method/attempt and `scoring_plan_sha256`, the existing
cache hash of `reference` WITHOUT fit_sha256/fit_provenance. No policy is defaulted.

The trusted recorder must publish `fit_event_record(stage, binding)` and return
its absolute path. Each publication is verified inside the observation callback.
Return `(fit, reference, link)` after successful return observation and hashing;
publish/retain `link` separately with CREATE_NEW. Post-return hashing errors retain
the result in FitObservationError(:fit_linked, ...), without refitting. This is
one local call, not an attempt allocator/restart guard or execution permission.
"""
function observe_linked_fit(design; reference::NamedTuple, options, path::AbstractString,
        expected, boundary, semantic_validator, record_event)
    reference, path = deepcopy(reference), String(path)
    observations = NamedTuple[]
    fit = observe_declared_fit(design; options, path, expected, boundary,
        semantic_validator = value -> begin
            _check_scoring_plan(value, reference)
            semantic_validator(value)
        end,
        record_event = (stage, binding) -> begin
            event_path = record_event(stage, binding)
            verified = _verified_record(event_path, fit_event_record(stage, binding), boundary;
                semantic_validator = _ -> nothing)
            push!(observations, (; stage, binding, verified.reference))
        end)
    input = (; path, content_hash = observations[1].binding.input_content_hash,
        file_sha256 = observations[1].binding.input_file_sha256)
    provenance = (; input, entered = observations[1].reference, returned = observations[2].reference)
    return _link_returned_fit(fit, reference, provenance)
end

"""
    score_linked_fit(fit, training_bytes, heldout_bytes, truth_records;
        reference, path, expected, boundary)

Read-only verification of the separately retained result link and all three
pinned input/event files, followed by the existing attempt-bound scorer. Missing,
changed, or unreconciled evidence rejects without repair, refitting, or rewriting
the observations. A failed score does not revoke a retained return observation.
Constructed objects/records remain test or declarative evidence, not proof of
execution; lifecycle counts and scientific acceptance remain outside this helper.
"""
function score_linked_fit(fit, training_bytes, heldout_bytes, truth_records;
        reference::NamedTuple, path, expected, boundary)
    fit, training_bytes, heldout_bytes, truth_records, reference = deepcopy(
        (fit, training_bytes, heldout_bytes, truth_records, reference))
    linked = _verified_record(path, expected, boundary; semantic_validator = _ -> nothing).data
    Archive._ld1b_exact_keys(linked, (:schema, :fit_sha256, :reference_sha256,
        :fit_provenance, :content_hash), "fit return link")
    linked["schema"] == "bayesianmgmfrm.anchor_fit_return_link.v1" &&
        linked["fit_sha256"] == BayesianMGMFRM._mfrm_anchor_fit_hash(fit) &&
        linked["reference_sha256"] == BayesianMGMFRM._cache_hash(reference) &&
        haskey(reference, :fit_provenance) &&
        linked["fit_provenance"] == Archive._ld1b_json_native(reference.fit_provenance) ||
        throw(ArgumentError("fit or scoring reference differs from the retained result link"))
    provenance = Archive._ld1b_exact_keys(linked["fit_provenance"],
        (:input, :entered, :returned), "fit provenance")
    declaration = _pinned_record(provenance["input"], boundary)
    _check_scoring_plan(declaration, Base.structdiff(reference, (; fit_sha256 = nothing, fit_provenance = nothing)))
    input = provenance["input"]
    binding = (; input_content_hash = input["content_hash"], input_file_sha256 = input["file_sha256"])
    for (key, stage) in (("entered", :fit_entered), ("returned", :fit_returned))
        event = _pinned_record(provenance[key], boundary)
        Archive._ld1b_encode_json_bytes(event) == Archive._ld1b_encode_json_bytes(fit_event_record(stage, binding)) ||
            throw(ArgumentError("fit observation stage or input binding differs"))
    end
    return BayesianMGMFRM._mfrm_anchor_score_attempt(fit, training_bytes,
        heldout_bytes, truth_records; reference)
end

"""
    recover_record(path, expected, staging_dir, boundary; semantic_validator)

Recover publication of one caller-retained, content-hashed JSON record after
its producer has stopped. The validator must throw on semantic rejection.
An absent target is reported, never republished. A valid single-link target is
read only; exactly one verified staging alias may be removed using the existing
reconciler. Other conflicts throw without replacing the target or restarting work.

This checks publication, not whether a fit ran. Use one stopped writer on a
trusted local, same-volume archive; no power-loss or cloud-sync guarantee.
"""
function recover_record(path::AbstractString, expected, staging_dir::AbstractString,
        boundary::AbstractString; semantic_validator)
    # ponytail: one stopped writer; add coordination only for a reviewed
    # concurrent-writer workflow, not as an inferred recovery feature.
    all(p -> isabspath(p) && normpath(p) == p, (path, staging_dir, boundary)) ||
        throw(ArgumentError("record recovery paths must be normalized and absolute"))
    Archive._ld1b_require_directory(boundary, boundary, "record boundary")
    Archive._ld1b_require_directory(dirname(path), boundary, "record parent")
    Archive._ld1b_reject_symlink_components(path, boundary)
    Archive._ld1b_reject_symlink_components(staging_dir, boundary)
    !Archive._ld1b_path_within(path, staging_dir) || throw(ArgumentError(
        "staging must not contain the publication target"))
    Archive._ld1b_path_occupied(staging_dir) &&
        Archive._ld1b_require_directory(staging_dir, boundary, "record staging")
    expected = deepcopy(expected)
    content_hash = Archive.ld1b_verify_archive_content_hash(expected)
    bytes = Archive._ld1b_encode_json_bytes(expected)
    semantic_validator(Archive._ld1b_json_native(expected))
    scope = (; content_hash, lifecycle_counts_available = false,
        validation_claim_allowed = false)
    if !Archive._ld1b_path_occupied(path)
        return (; scope..., status = :not_published, file_sha256 = nothing,
            staging_alias_removed = false)
    end
    snapshot = Archive._ld1b_read_json_snapshot(path, boundary, "anchor record";
        require_single_link = false)
    snapshot.bytes == bytes || throw(ArgumentError(
        "published record differs from the separately retained expected bytes"))
    Archive.ld1b_verify_archive_content_hash(snapshot.parsed)
    semantic_validator(snapshot.parsed)
    snapshot.nlink in (1, 2) || throw(ArgumentError(
        "record has ambiguous hard links; preserve it for review"))
    if snapshot.nlink == 2
        Archive.ld1b_reconcile_json_create_new_staging_alias(
            path, expected, staging_dir, boundary; semantic_validator,
            artifact_label = "anchor record")
    end
    return (; scope..., status = :published, file_sha256 = snapshot.sha256,
        staging_alias_removed = snapshot.nlink == 2)
end

end # module
