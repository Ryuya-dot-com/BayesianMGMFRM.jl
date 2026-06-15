# evidence_metadata.jl -- reproducibility metadata helpers.

using Dates
using InteractiveUtils
using LinearAlgebra
using Pkg

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
