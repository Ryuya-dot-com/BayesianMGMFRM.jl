using BayesianMGMFRM
using BayesianMGMFRM.Legacy
using Test
using SHA

const _run_evidence_optional = getfield(
    BayesianMGMFRM,
    :_evidence_optional,
)
const _try_read_evidence_command = getfield(
    BayesianMGMFRM,
    :_evidence_try_read,
)

@testset "package metadata reads resolved manifests without loading Pkg" begin
    B = BayesianMGMFRM
    original = Base.active_project()
    for format in (1, 2)
        mktempdir() do dir
            project = joinpath(dir, "Project.toml")
            write(project, "[deps]\nLocalDep = \"00000000-0000-0000-0000-000000000001\"\n")
            prefix = format == 2 ? "manifest_format = \"2.0\"\n" : ""
            section = format == 2 ? "deps." : ""
            write(joinpath(dir, "Manifest.toml"), prefix * """
            [[$(section)LocalDep]]
            uuid = "00000000-0000-0000-0000-000000000001"
            version = "2.3.4"
            path = "../local-dependency"
            [[$(section)IndirectDep]]
            uuid = "00000000-0000-0000-0000-000000000002"
            path = "../indirect-dependency"
            """)
            try
                Base.set_active_project(project)
                public = B._evidence_package_status()
                @test Set(keys(public)) == Set(["LocalDep"])
                @test public["LocalDep"]["version"] == "2.3.4"
                @test public["LocalDep"]["source"] === nothing
                @test public["LocalDep"]["source_basename"] == "local-dependency"
                private = B._evidence_package_status(;direct_only=false,include_paths=true)
                @test length(private) == 2
                @test private["LocalDep"]["source"] == normpath(joinpath(dir,"../local-dependency"))
                @test private["LocalDep"]["is_tracking_path"]
                @test !private["IndirectDep"]["is_direct_dep"]
                @test private["IndirectDep"]["version"] === nothing
                write(joinpath(dir,"Manifest.toml"), prefix)
                @test_throws ArgumentError B._evidence_package_status()
                rm(joinpath(dir,"Manifest.toml"))
                @test_throws ArgumentError B._evidence_package_status()
            finally
                Base.set_active_project(original)
            end
        end
    end
end

@testset "homonymous dependencies retain UUID identity" begin
    mktempdir() do dir
        project = joinpath(dir,"Project.toml")
        write(project,"[deps]\nTwin = \"00000000-0000-0000-0000-000000000001\"\n")
        for direct_first in (true,false), format in (1,2)
            prefix = format == 2 ? "manifest_format = \"2.0\"\n" : ""
            section = format == 2 ? "deps." : ""
            records = ["""
                [[$(section)Twin]]
                uuid = "00000000-0000-0000-0000-00000000000$i"
                version = "$i.0.0"
                path = "../twin-$i"
                """ for i in (direct_first ? (1,2) : (2,1))]
            write(joinpath(dir,"Manifest.toml"),prefix*join(records))
            status = BayesianMGMFRM._evidence_package_status(;project,direct_only=false)
            @test length(status) == 2
            @test status["Twin"]["uuid"] == "00000000-0000-0000-0000-000000000001"
            @test status["Twin"]["is_direct_dep"]
            @test status["Twin@00000000-0000-0000-0000-000000000002"]["version"] == "2.0.0"
            @test length(BayesianMGMFRM._evidence_package_status(;project)) == 1
        end
    end
end

@testset "LOAD_PATH package and active environment are distinct" begin
    original = Base.active_project()
    previous_load_path = copy(LOAD_PATH)
    mktempdir() do dir
        project = joinpath(dir,"Project.toml")
        write(project,"[deps]\n")
        write(joinpath(dir,"Manifest.toml"),"manifest_format = \"2.0\"\n")
        try
            Base.set_active_project(project)
            root = dirname(dirname(pathof(BayesianMGMFRM)))
            pushfirst!(LOAD_PATH,root)
            @test isempty(BayesianMGMFRM._evidence_package_status())
            env = BayesianMGMFRM._evidence_package_environment(;include_paths=true)
            @test env["project"] == joinpath(root,"Project.toml")
            @test haskey(env["packages"],"Distributions")
            @test env["project_sha256"] == bytes2hex(sha256(read(env["project"])))
            @test env["manifest_sha256"] == bytes2hex(sha256(read(env["manifest"])))
            public = BayesianMGMFRM._evidence_package_environment()
            @test public["project"] === nothing
            @test public["manifest"] === nothing
            @test all(d["source"] === nothing for d in values(public["packages"]))
        finally
            Base.set_active_project(original)
            empty!(LOAD_PATH); append!(LOAD_PATH,previous_load_path)
        end
    end
end

@testset "evidence metadata remains usable after optional probe failure" begin
    issues = Any[]
    available = _run_evidence_optional(:unit_probe; issues) do
        "available"
    end
    @test available == "available"
    @test isempty(issues)

    unavailable = _run_evidence_optional(
        :unit_probe;
        issues,
        fallback = "fallback",
    ) do
        throw(ArgumentError("expected test failure"))
    end
    @test unavailable == "fallback"
    @test only(issues) == (;
        status = :unavailable,
        stage = :unit_probe,
        reason = :invalid_value,
    )

    noisy_issues = Any[]
    noisy_command = `$(Base.julia_cmd()) --startup-file=no -e "println(stderr, \"optional probe noise\"); exit(1)"`
    noisy_result, stderr_text = mktemp() do _, captured_stderr
        result = redirect_stderr(captured_stderr) do
            _try_read_evidence_command(
                noisy_command;
                issues = noisy_issues,
                stage = :noisy_command,
            )
        end
        flush(captured_stderr)
        seekstart(captured_stderr)
        return result, read(captured_stderr, String)
    end
    @test isnothing(noisy_result)
    @test isempty(stderr_text)
    @test only(noisy_issues).stage === :noisy_command
    @test only(noisy_issues).reason === :command_failed

    metadata = evidence_metadata(; include_packages = false)
    @test metadata["collection"]["status"] in (:complete, :partial)
    @test haskey(metadata, "git")
    @test haskey(metadata, "hashes")
    @test haskey(metadata["hashes"], "active_project_sha256")
    @test metadata["hashes"]["active_project"] === nothing
    @test metadata["software"]["julia"]["project"] === nothing
    @test all(
        issue -> issue.status === :unavailable &&
            issue.stage isa Symbol && issue.reason isa Symbol,
        metadata["collection"]["issues"],
    )
    @test metadata["packages"] == Dict{String,Any}()

    metadata_with_packages = evidence_metadata()
    @test metadata_with_packages["packages"] isa Dict{String,Any}

    withenv("PATH" => "") do
        degraded = evidence_metadata(; include_packages = false)
        issue_stages = Set(issue.stage for issue in
            degraded["collection"]["issues"])
        @test degraded["collection"]["status"] === :partial
        @test :r_version in issue_stages
        @test :git_root in issue_stages
        @test !degraded["git"]["available"]
    end
end

@testset "evidence Manifest binding follows the running Julia loader (no fits)" begin
    resolve_manifest = BayesianMGMFRM._evidence_manifest_path
    hashes = BayesianMGMFRM._evidence_project_hashes
    digest = BayesianMGMFRM._evidence_file_sha256
    function with_project(f, project)
        previous = Base.ACTIVE_PROJECT[]
        try
            Base.set_active_project(project)
            return f()
        finally
            Base.set_active_project(previous)
        end
    end
    original_project = Base.active_project()
    # Exhaust every subset of the loader's recognized filenames; unsupported
    # major-only and other-minor files must never become an invented fallback.
    names = Base.manifest_names
    for project_name in ("Project.toml", "JuliaProject.toml"), mask in 0:(2^length(names) - 1)
        mktempdir() do directory
            project = joinpath(directory, project_name)
            write(project, "")
            write(joinpath(directory, "Manifest-v$(VERSION.major).toml"), "major-only decoy")
            write(joinpath(directory, "Manifest-v99.42.toml"), "other-version decoy")
            selected = [joinpath(directory, name) for (n, name) in pairs(names) if mask & (1 << (n - 1)) != 0]
            foreach(path -> write(path, basename(path)), selected)
            expected = isempty(selected) ? nothing : first(selected)
            @test resolve_manifest(project) == Base.project_file_manifest_path(project) == expected
            with_project(project) do
                issues = Any[]
                private = hashes(; include_paths = true, issues)
                portable = hashes()
                @test isempty(issues)
                @test private["active_project"] == project
                @test private["active_project_sha256"] == bytes2hex(sha256(read(project)))
                @test private["manifest"] == expected
                @test private["manifest_sha256"] == digest(expected)
                @test private["manifest_basename"] == (expected === nothing ? nothing : basename(expected))
                @test portable["active_project"] === portable["manifest"] === nothing
                @test portable["manifest_sha256"] == private["manifest_sha256"]
                @test portable["active_project_sha256"] == private["active_project_sha256"]
                cd(dirname(directory)) do
                    @test hashes(; include_paths = true) == private
                end
            end
        end
    end
    for absolute in (false, true)
        mktempdir() do directory
            environment = mkpath(joinpath(directory, "environment"))
            project = joinpath(environment, "Project.toml")
            custom = joinpath(directory, "custom.toml")
            fallback = joinpath(environment, "Manifest.toml")
            write(project, "manifest = $(repr(absolute ? custom : "../custom.toml"))\n")
            write(custom, "initial bytes")
            write(fallback, "fallback bytes")
            with_project(project) do
                saved = hashes(; include_paths = true)
                @test saved["manifest"] == custom == Base.project_file_manifest_path(project)
                @test saved["manifest_sha256"] == bytes2hex(sha256(read(custom)))
                write(custom, "changed bytes")
                @test hashes()["manifest_sha256"] != saved["manifest_sha256"]
                @test hashes()["manifest_sha256"] == bytes2hex(sha256(read(custom)))
                mv(custom, joinpath(directory, "retained-custom.toml"))
                @test digest(custom) === nothing
                @test hashes()["manifest_basename"] == basename(fallback)
                @test resolve_manifest(project) == Base.project_file_manifest_path(project) == fallback
            end
        end
    end
    mktempdir() do directory
        root_project = joinpath(directory, "Project.toml")
        root_manifest = joinpath(directory, "Manifest.toml")
        child = mkpath(joinpath(directory, "child"))
        project = joinpath(child, "Project.toml")
        child_manifest = joinpath(child, "Manifest.toml")
        write(root_project, "[workspace]\nprojects = [\"child\"]\n")
        write(project, "")
        write(root_manifest, "root bytes")
        write(child_manifest, "child bytes")
        expected = isdefined(Base, :workspace_manifest) ? root_manifest : child_manifest
        with_project(project) do
            @test hashes(; include_paths = true)["manifest"] == expected
            @test hashes()["manifest_sha256"] == bytes2hex(sha256(read(expected)))
        end
        malformed = joinpath(directory, "malformed.toml")
        write(malformed, "manifest = [not valid TOML")
        with_project(malformed) do
            issues = Any[]
            recorded = hashes(; issues)
            @test recorded["manifest_sha256"] === nothing
            @test recorded["active_project_sha256"] == bytes2hex(sha256(read(malformed)))
            @test only(issues).stage === :manifest_resolve
            @test only(issues).status === :unavailable
            @test BayesianMGMFRM._evidence_collection_report(issues)["status"] === :partial
            @test !occursin(directory, string(issues))
        end
        for absent in (nothing, missing, 42, directory, joinpath(directory, "absent.toml"))
            @test resolve_manifest(absent) === nothing
        end
    end
    @test Base.active_project() == original_project
end
