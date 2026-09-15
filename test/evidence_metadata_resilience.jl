using BayesianMGMFRM
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
