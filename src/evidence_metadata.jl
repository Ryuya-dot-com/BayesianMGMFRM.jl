# evidence_metadata.jl -- reproducibility metadata helpers.

using Dates
using LinearAlgebra
using Pkg
using SHA

function _evidence_try_read(cmd)
    try
        return readchomp(cmd)
    catch
        return nothing
    end
end

function _evidence_total_memory()
    if isdefined(Sys, :total_memory)
        try
            return Sys.total_memory()
        catch
            return nothing
        end
    end
    value = _evidence_try_read(`sysctl -n hw.memsize`)
    isnothing(value) && return nothing
    try
        return parse(Int, value)
    catch
        return nothing
    end
end

function _evidence_cmdstan_metadata()
    path = get(ENV, "CMDSTAN", get(ENV, "CMDSTAN_HOME", ""))
    if isempty(path)
        root = joinpath(homedir(), ".cmdstan")
        if isdir(root)
            dirs = sort(filter(d -> startswith(d, "cmdstan-"), readdir(root)))
            if !isempty(dirs)
                path = joinpath(root, last(dirs))
            end
        end
    end
    version = nothing
    if !isempty(path)
        m = match(r"cmdstan-([0-9.]+)", basename(path))
        version = isnothing(m) ? nothing : m.captures[1]
    end
    return Dict{String,Any}("path" => isempty(path) ? nothing : path,
                            "version" => version)
end

function _evidence_package_status(; direct_only::Bool = true)
    out = Dict{String,Any}()
    for (uuid, dep) in Pkg.dependencies()
        direct_only && !dep.is_direct_dep && continue
        out[dep.name] = Dict{String,Any}(
            "version" => isnothing(dep.version) ? nothing : string(dep.version),
            "uuid" => string(uuid),
            "is_direct_dep" => dep.is_direct_dep,
            "is_tracking_path" => dep.is_tracking_path,
            "source" => dep.source,
        )
    end
    return out
end

function _evidence_file_sha256(path)
    path isa AbstractString || return nothing
    isfile(path) || return nothing
    try
        return bytes2hex(sha256(read(path)))
    catch
        return nothing
    end
end

function _evidence_git_metadata()
    root = _evidence_try_read(`git rev-parse --show-toplevel`)
    isnothing(root) && return Dict{String,Any}(
        "available" => false,
        "root" => nothing,
        "commit" => nothing,
        "branch" => nothing,
        "dirty" => nothing,
        "status_short_sha256" => nothing,
    )
    status_short = _evidence_try_read(`git status --short`)
    return Dict{String,Any}(
        "available" => true,
        "root" => root,
        "commit" => _evidence_try_read(`git rev-parse HEAD`),
        "branch" => _evidence_try_read(`git rev-parse --abbrev-ref HEAD`),
        "dirty" => isnothing(status_short) ? nothing : !isempty(status_short),
        "status_short_sha256" => isnothing(status_short) ?
            nothing : bytes2hex(sha256(codeunits(status_short))),
    )
end

function _evidence_project_hashes()
    project = Base.active_project()
    project_dir = isnothing(project) ? nothing : dirname(project)
    manifest = isnothing(project_dir) ? nothing : joinpath(project_dir, "Manifest.toml")
    return Dict{String,Any}(
        "active_project" => project,
        "active_project_sha256" => _evidence_file_sha256(project),
        "manifest" => manifest,
        "manifest_sha256" => _evidence_file_sha256(manifest),
    )
end

"""
    evidence_metadata(; include_packages = true)

Return reproducibility metadata for the active Julia session, including Julia,
OS, BLAS, optional R/CmdStan discovery, git/project hashes, and direct package
status.
"""
function evidence_metadata(; include_packages::Bool = true)
    cpu = Sys.cpu_info()
    cpu_model = isempty(cpu) ? nothing : getproperty(first(cpu), :model)
    return Dict{String,Any}(
        "captured_at" => string(now()),
        "hardware" => Dict{String,Any}(
            "cpu_model" => cpu_model,
            "cpu_threads" => length(cpu),
            "total_memory_bytes" => _evidence_total_memory(),
        ),
        "software" => Dict{String,Any}(
            "os" => Dict{String,Any}(
                "kernel" => Sys.KERNEL,
                "machine" => Sys.MACHINE,
                "word_size" => Sys.WORD_SIZE,
            ),
            "julia" => Dict{String,Any}(
                "version" => string(VERSION),
                "project" => Base.active_project(),
                "threads" => Threads.nthreads(),
                "depot_path" => DEPOT_PATH,
                "load_path" => LOAD_PATH,
            ),
            "r" => Dict{String,Any}(
                "version" => _evidence_try_read(`Rscript -e "cat(R.version.string)"`),
            ),
            "cmdstan" => _evidence_cmdstan_metadata(),
            "blas" => Dict{String,Any}(
                "threads" => BLAS.get_num_threads(),
                "config" => string(BLAS.get_config()),
            ),
        ),
        "git" => _evidence_git_metadata(),
        "hashes" => _evidence_project_hashes(),
        "execution" => Dict{String,Any}(
            "julia_num_threads_env" => get(ENV, "JULIA_NUM_THREADS", nothing),
            "omp_num_threads" => get(ENV, "OMP_NUM_THREADS", nothing),
            "openblas_num_threads" => get(ENV, "OPENBLAS_NUM_THREADS", nothing),
            "blas_num_threads" => BLAS.get_num_threads(),
            "power_thermal_notes" => get(ENV, "GMFRM_POWER_NOTES", "not recorded"),
        ),
        "packages" => include_packages ? _evidence_package_status() : Dict{String,Any}(),
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
unsupported-claim flags, and raw-data/anonymization status.
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
        environment_policy = (;
            include_environment,
            require_project_hash = true,
            require_git_status_hash = true,
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
            has_environment_policy = true,
            has_execution_policy = true,
            has_claim_policy = true,
            has_raw_data_policy = true,
        ),
    )
end
