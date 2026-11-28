using Pkg, TOML, UUIDs

const release_commit = "ae61f103b14d8b3af6ba459b37020627dd58a98d"
const repository = "https://github.com/Ryuya-dot-com/BayesianMGMFRM.jl"
const package_id = UUID("1c3fdc16-45de-4463-900f-cd2a5999ffa5")
const tables_id = UUID("bd369af6-aec1-5ad0-b16a-f7cc5008161c")

function setup(project, source)
    VERSION >= v"1.10.8" || error("Julia 1.10.8 or later is required")
    ENV["JULIA_PKG_PRECOMPILE_AUTO"] = "0"
    target = isempty(source) ? release_commit : realpath(source)
    existing = ispath(project)
    if !existing
        parent = mkpath(dirname(project))
        mktempdir(parent) do stage
            Pkg.activate(stage)
            if isempty(source)
                Pkg.add(PackageSpec(url=repository, rev=release_commit))
            else
                config = TOML.parsefile(joinpath(target, "Project.toml"))
                get(config, "uuid", "") == string(package_id) || error("Unexpected local package")
                Pkg.develop(path=target)
            end
            Pkg.add(PackageSpec(name="Tables", uuid=tables_id, version="1"))
            Pkg.instantiate()
            Pkg.precompile()
            write(joinpath(stage, "bridge-source.txt"), target)
            # A competing installer can finish first. Check its identity below.
            try
                mv(stage, project)
            catch
                isdir(project) || rethrow()
            end
        end
    end
    marker = joinpath(project, "bridge-source.txt")
    isfile(marker) && read(marker, String) == target ||
        error("Choose a separate bridge project for this source: " * project)
    Pkg.activate(project)
    for filename in ("Project.toml", "Manifest.toml")
        isfile(joinpath(project, filename)) || error("Incomplete bridge environment: " * filename)
    end
    info = Pkg.dependencies()[package_id]
    (isempty(source) ? (info.git_revision == release_commit && info.git_source == repository) :
        (info.is_tracking_path && realpath(info.source) == target)) || error("Package source mismatch")
    Pkg.project().dependencies["Tables"] == tables_id || error("Missing bridge dependency Tables")
    if existing
        Pkg.instantiate()
        Pkg.precompile()
    end
end

setup(abspath(ARGS[1]), length(ARGS) == 2 ? ARGS[2] : "")
