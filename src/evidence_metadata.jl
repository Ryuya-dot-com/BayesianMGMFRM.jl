# evidence_metadata.jl -- reproducibility metadata helpers.

using Dates
using LinearAlgebra
using Pkg
using SHA

function _evidence_failure_reason(error)
    error isa Base.ProcessFailedException && return :command_failed
    error isa Base.IOError && return :io_error
    error isa ArgumentError && return :invalid_value
    return :unexpected_error
end

function _evidence_optional(operation::F, stage::Symbol;
        issues = nothing,
        fallback = nothing) where {F}
    try
        return operation()
    catch error
        if issues !== nothing
            push!(issues, (;
                status = :unavailable,
                stage,
                reason = _evidence_failure_reason(error),
            ))
        end
        return fallback
    end
end

function _evidence_try_read(cmd;
        dir = nothing,
        issues = nothing,
        stage::Symbol = :command_read)
    return _evidence_optional(stage; issues) do
        resolved = dir === nothing ? cmd : Cmd(cmd; dir)
        readchomp(pipeline(resolved; stderr = devnull))
    end
end

function _evidence_total_memory(; issues = nothing)
    if isdefined(Sys, :total_memory)
        memory = _evidence_optional(:total_memory; issues) do
            Sys.total_memory()
        end
        !isnothing(memory) && return memory
    end
    command = _evidence_try_read(
        `sysctl -n hw.memsize`;
        issues,
        stage = :total_memory_command,
    )
    isnothing(command) && return nothing
    return _evidence_optional(:total_memory_parse; issues) do
        parse(Int, command)
    end
end

_evidence_path_basename(path) =
    path isa AbstractString && !isempty(path) ? basename(normpath(path)) : nothing

function _evidence_cmdstan_metadata(; include_paths::Bool = false)
    path = _cmdstan_resolve_root(nothing).path
    version_number = path === nothing ? nothing :
        _cmdstan_version_from_name(path)
    version = version_number === nothing ? nothing : string(version_number)
    return Dict{String,Any}(
        "path" => include_paths ? path : nothing,
        "path_basename" => _evidence_path_basename(path),
        "version" => version,
    )
end

function _evidence_package_status(;
        direct_only::Bool = true,
        include_paths::Bool = false)
    out = Dict{String,Any}()
    for (uuid, dep) in Pkg.dependencies()
        direct_only && !dep.is_direct_dep && continue
        out[dep.name] = Dict{String,Any}(
            "version" => isnothing(dep.version) ? nothing : string(dep.version),
            "uuid" => string(uuid),
            "is_direct_dep" => dep.is_direct_dep,
            "is_tracking_path" => dep.is_tracking_path,
            "source" => include_paths ? dep.source : nothing,
            "source_basename" => _evidence_path_basename(dep.source),
        )
    end
    return out
end

function _evidence_file_sha256(path;
        issues = nothing,
        stage::Symbol = :file_read)
    path isa AbstractString || return nothing
    isfile(path) || return nothing
    return _evidence_optional(stage; issues) do
        bytes2hex(sha256(read(path)))
    end
end

function _evidence_manifest_path(project_dir;
        version::VersionNumber = VERSION)
    project_dir isa AbstractString || return nothing
    candidates = (
        joinpath(project_dir,
            "Manifest-v$(version.major).$(version.minor).toml"),
        joinpath(project_dir, "Manifest-v$(version.major).toml"),
        joinpath(project_dir, "Manifest.toml"),
    )
    index = findfirst(isfile, candidates)
    return index === nothing ? nothing : candidates[index]
end

function _evidence_git_metadata(;
        include_paths::Bool = false,
        issues = nothing)
    project = Base.active_project()
    project_dir = isnothing(project) ? nothing : dirname(project)
    root = isnothing(project_dir) ? nothing :
        _evidence_try_read(
            `git rev-parse --show-toplevel`;
            dir = project_dir,
            issues,
            stage = :git_root,
        )
    isnothing(root) && return Dict{String,Any}(
        "available" => false,
        "root" => nothing,
        "root_basename" => nothing,
        "commit" => nothing,
        "branch" => nothing,
        "dirty" => nothing,
        "status_short_sha256" => nothing,
    )
    status_short = _evidence_try_read(
        `git status --short`;
        dir = root,
        issues,
        stage = :git_status,
    )
    commit = _evidence_try_read(
        `git rev-parse HEAD`;
        dir = root,
        issues,
        stage = :git_commit,
    )
    branch = _evidence_try_read(
        `git rev-parse --abbrev-ref HEAD`;
        dir = root,
        issues,
        stage = :git_branch,
    )
    return Dict{String,Any}(
        "available" => true,
        "root" => include_paths ? root : nothing,
        "root_basename" => _evidence_path_basename(root),
        "commit" => commit,
        "branch" => branch,
        "dirty" => isnothing(status_short) ? nothing : !isempty(status_short),
        "status_short_sha256" => isnothing(status_short) ?
            nothing : bytes2hex(sha256(codeunits(status_short))),
    )
end

function _evidence_project_hashes(;
        include_paths::Bool = false,
        issues = nothing)
    project = Base.active_project()
    project_dir = isnothing(project) ? nothing : dirname(project)
    manifest = _evidence_manifest_path(project_dir)
    return Dict{String,Any}(
        "active_project" => include_paths ? project : nothing,
        "active_project_basename" => _evidence_path_basename(project),
        "active_project_sha256" => _evidence_file_sha256(
            project;
            issues,
            stage = :active_project_read,
        ),
        "manifest" => include_paths ? manifest : nothing,
        "manifest_basename" => _evidence_path_basename(manifest),
        "manifest_sha256" => _evidence_file_sha256(
            manifest;
            issues,
            stage = :manifest_read,
        ),
    )
end

function _evidence_collection_report(issues)
    return Dict{String,Any}(
        "status" => isempty(issues) ? :complete : :partial,
        "issues" => Tuple(issues),
    )
end

"""
    evidence_metadata(; include_packages = true, include_paths = false)

Return reproducibility metadata for the active Julia session, including Julia,
OS, BLAS, optional R/CmdStan discovery, git/project hashes, and direct package
status. Machine-local paths are omitted by default while safe basenames and
content hashes are retained. Set `include_paths = true` only when a private
reproduction record explicitly requires complete local paths and free-form
execution notes. Optional probe failures do not stop metadata creation;
`collection.issues` records their stage and short reason.
"""
function evidence_metadata(;
        include_packages::Bool = true,
        include_paths::Bool = false)
    issues = Any[]
    cpu = Sys.cpu_info()
    cpu_model = isempty(cpu) ? nothing : getproperty(first(cpu), :model)
    memory = _evidence_total_memory(; issues)
    r_version = _evidence_try_read(
        `Rscript -e "cat(R.version.string)"`;
        issues,
        stage = :r_version,
    )
    git = _evidence_git_metadata(; include_paths, issues)
    hashes = _evidence_project_hashes(; include_paths, issues)
    cmdstan = _evidence_optional(
        :cmdstan_discovery;
        issues,
        fallback = Dict{String,Any}(
            "path" => nothing,
            "path_basename" => nothing,
            "version" => nothing,
        ),
    ) do
        _evidence_cmdstan_metadata(; include_paths)
    end
    packages = include_packages ?
        _evidence_optional(
            :package_status;
            issues,
            fallback = Dict{String,Any}(),
        ) do
            _evidence_package_status(; include_paths)
        end :
        Dict{String,Any}()
    return Dict{String,Any}(
        "captured_at" => string(now()),
        "collection" => _evidence_collection_report(issues),
        "hardware" => Dict{String,Any}(
            "cpu_model" => cpu_model,
            "cpu_threads" => length(cpu),
            "total_memory_bytes" => memory,
        ),
        "software" => Dict{String,Any}(
            "os" => Dict{String,Any}(
                "kernel" => Sys.KERNEL,
                "machine" => Sys.MACHINE,
                "word_size" => Sys.WORD_SIZE,
            ),
            "julia" => Dict{String,Any}(
                "version" => string(VERSION),
                "project" => include_paths ? Base.active_project() : nothing,
                "project_basename" =>
                    _evidence_path_basename(Base.active_project()),
                "threads" => Threads.nthreads(),
                "depot_path" => include_paths ? copy(DEPOT_PATH) : nothing,
                "depot_basenames" =>
                    [_evidence_path_basename(path) for path in DEPOT_PATH],
                "load_path" => include_paths ? copy(LOAD_PATH) : nothing,
                "load_path_basenames" =>
                    [_evidence_path_basename(path) for path in LOAD_PATH],
            ),
            "r" => Dict{String,Any}(
                "version" => r_version,
            ),
            "cmdstan" => cmdstan,
            "blas" => Dict{String,Any}(
                "threads" => BLAS.get_num_threads(),
                "config" => string(BLAS.get_config()),
            ),
        ),
        "git" => git,
        "hashes" => hashes,
        "execution" => Dict{String,Any}(
            "julia_num_threads_env" => get(ENV, "JULIA_NUM_THREADS", nothing),
            "omp_num_threads" => get(ENV, "OMP_NUM_THREADS", nothing),
            "openblas_num_threads" => get(ENV, "OPENBLAS_NUM_THREADS", nothing),
            "blas_num_threads" => BLAS.get_num_threads(),
            "power_thermal_notes" => include_paths ?
                get(ENV, "GMFRM_POWER_NOTES", nothing) : nothing,
            "power_thermal_notes_recorded" =>
                haskey(ENV, "GMFRM_POWER_NOTES"),
        ),
        "packages" => packages,
    )
end

function _evidence_policy_required_rows()
    return (
        (field = :schema, requirement = :schema_version, status = :required,
            note = "artifact records its schema name and schema version suffix"),
        (field = :object, requirement = :artifact_object_kind, status = :required,
            note = "artifact records the object kind being serialized"),
        (field = :content_hash, requirement = :sha256_content_hash, status = :required,
            note = "artifact or export records a SHA-256 hash over canonicalized content"),
        (field = :archive_manifest, requirement = :archive_or_export_manifest, status = :required,
            note = "artifact records source path, label, schema, and content hash where applicable"),
        (field = :environment, requirement = :environment_or_omission_flag, status = :required,
            note = "artifact records environment metadata or explicitly marks it omitted"),
        (field = :hashes, requirement = :package_git_environment_hashes, status = :required,
            note = "environment metadata records active project, manifest, and git status hashes when available"),
        (field = :rng, requirement = :seed_or_rng_replay_policy, status = :required,
            note = "fit evidence records seed/RNG replay policy or an explicit not-applicable marker"),
        (field = :sampler_controls, requirement = :sampler_controls, status = :required,
            note = "fit evidence records backend, warmup, draws, chains, step size, and related sampler controls"),
        (field = :cache_provenance, requirement = :cache_or_rerun_provenance, status = :required,
            note = "cached evidence records cache key/path/hash, while non-cache evidence records not-applicable"),
        (field = :unsupported_claims, requirement = :unsupported_claim_flags, status = :required,
            note = "artifact records claims that remain blocked by the current release scope"),
        (field = :raw_data, requirement = :raw_data_or_anonymization_status, status = :required,
            note = "artifact records whether raw row-level data are omitted, anonymized, or source-controlled privately"),
    )
end

"""
    evidence_artifact_schema_policy(artifact_kind = :general; kwargs...)

Return the machine-readable schema policy for review artifacts. The policy
defines required provenance fields for schema versioning, content hashes,
package/git/environment hashes, seed and sampler controls, cache provenance,
unsupported-claim flags, and raw-data/anonymization status. The additive
scientific-payload policy separates an explicit schema-specific scientific
projection from the exact-file hash while legacy v1 artifacts are migrated.
"""
function evidence_artifact_schema_policy(artifact_kind::Symbol = :general;
        include_environment::Bool = true,
        include_cache_provenance::Bool = true,
        raw_data_status::Symbol = :not_included,
        unsupported_claims = (
            :broad_generalized_fit,
            :dff_model_effects,
            :model_weight_or_superiority,
            :sparse_mgmfrm_superiority,
        ))
    required_fields = _evidence_policy_required_rows()
    normalized_claims = Tuple(Symbol(claim) for claim in unsupported_claims)
    return (;
        schema = "bayesianmgmfrm.evidence_artifact_schema_policy.v1",
        object = :evidence_artifact_schema_policy,
        artifact_kind,
        status = :recorded,
        required_fields,
        hash_policy = (;
            algorithm = :sha256,
            canonicalization = :cache_stable_json_without_hash_metadata,
            required = true,
        ),
        scientific_payload_hash_policy = (;
            payload_field = :scientific_payload,
            digest_field = :scientific_payload_sha256,
            algorithm = :sha256,
            scope = :explicit_schema_specific_projection,
            canonicalization = :local_json_sorted_compact_v1,
            projection_policy = :explicit_schema_contract,
            schema_contract_requires = (
                :expected_schema,
                :required_top_level_fields,
                :allowed_top_level_fields,
            ),
            implementation_scope = :repository_tooling,
            artifact_integration_status = :staged,
            semantic_equivalence_comparison_status = :not_yet_integrated,
            legacy_absence_allowed_for_inventory = true,
            legacy_absence_verifies_equivalence = false,
            verify_if_present = true,
            semantic_gate_requires_verified_digest = true,
            exact_file_sha256_retained = true,
        ),
        environment_policy = (;
            include_environment,
            record_project_hash_when_available = include_environment,
            record_git_status_hash_when_available = include_environment,
            allow_missing_git_checkout = true,
            require_package_status_or_omission_flag = true,
        ),
        execution_policy = (;
            include_cache_provenance,
            require_seed_or_rng_policy = true,
            require_sampler_controls_or_not_applicable = true,
            require_cache_provenance_or_not_applicable = true,
        ),
        claim_policy = (;
            unsupported_claims = normalized_claims,
            require_unsupported_claim_flags = true,
            public_model_weight_claims_allowed = false,
            sparse_superiority_claims_allowed = false,
        ),
        raw_data_policy = (;
            status = raw_data_status,
            public_row_level_export_allowed = raw_data_status === :anonymized_public,
            require_anonymization_status = true,
        ),
        summary = (;
            n_required_fields = length(required_fields),
            n_unsupported_claims = length(normalized_claims),
            has_hash_policy = true,
            has_scientific_payload_hash_policy = true,
            has_environment_policy = true,
            has_execution_policy = true,
            has_claim_policy = true,
            has_raw_data_policy = true,
        ),
    )
end
