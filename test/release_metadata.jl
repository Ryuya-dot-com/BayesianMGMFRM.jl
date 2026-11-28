module ReleaseMetadataChecks

using Test
include(joinpath(@__DIR__, "..", "scripts", "release_metadata.jl"))

module DistributionAssembly
include(joinpath(@__DIR__, "..", "scripts", "distribution_archive_smoke.jl"))
end

@testset "Distribution keeps the public roadmap and excludes internal files" begin
    paths = DistributionAssembly.candidate_paths()
    @test "docs/src/roadmap.md" in paths
    @test "ROADMAP.md" ∉ paths
    @test all(path -> !startswith(replace(path, '\\' => '/'), "docs/internal/"), paths)
end

@testset "Release version and citation consistency" begin
    root = dirname(@__DIR__)
    @test ReleaseMetadata.check(root) isa NamedTuple
    mktempdir() do dir
        write(joinpath(dir, "Project.toml"), "version = \"0.2.0\"\n")
        citation = "cff-version: 1.2.0\nversion: \"0.2.0\"\n"
        news = "# Release notes\n\n## 0.2.0 (unreleased)\n\n## 0.1.9 (2026-01-01)\n"
        function set_metadata(cff = citation, notes = news)
            write(joinpath(dir, "CITATION.cff"), cff)
            write(joinpath(dir, "NEWS.md"), notes)
        end
        set_metadata()
        @test ReleaseMetadata.check(dir).unreleased
        @test ReleaseMetadata.check(dir).date_released === nothing
        for value in ("0.2.0", "'0.2.0'", "\"0.2.0\" # selected version")
            set_metadata("version: $value\nreferences:\n  - version: 9.9.9\n")
            @test ReleaseMetadata.check(dir).version == v"0.2.0"
        end
        for bad_cff in (
            replace(citation, "0.2.0" => "0.1.9"),
            "cff-version: 1.2.0\n",
            citation * "version: 0.2.0\n",
            "version:\n  - 0.2.0\n",
            "version: \"0.2.0'\n",
            citation * "date-released: \"2026-01-01\"\n",
            citation * "date-released:\n",
        )
            set_metadata(bad_cff)
            @test_throws ErrorException ReleaseMetadata.check(dir)
        end
        for bad_news in (
            replace(news, "0.2.0" => "0.3.0"),
            "# Release notes\n",
            "## 0.2.0\n",
            replace(news, "## 0.2.0" => "- Unscoped change\n\n## 0.2.0"),
            replace(news, "## 0.2.0" => "Unscoped prose\n\n## 0.2.0"),
            replace(news, "# Release notes\n\n" => ""),
        )
            set_metadata(citation, bad_news)
            @test_throws ErrorException ReleaseMetadata.check(dir)
        end
        released = "# Release notes\n\n## 0.2.0 (2026-10-19)\n"
        dated = citation * "date-released: \"2026-10-19\"\n"
        set_metadata(dated, released)
        @test !ReleaseMetadata.check(dir).unreleased
        @test ReleaseMetadata.check(dir).date_released == "2026-10-19"
        for bad_cff in (citation, replace(dated, "2026-10-19" => "2026-10-18"),
                       dated * "date-released: 2026-10-19\n")
            set_metadata(bad_cff, released)
            @test_throws ErrorException ReleaseMetadata.check(dir)
        end
        set_metadata(replace(dated, "2026-10-19" => "2026-02-30"),
                     "# Release notes\n\n## 0.2.0 (2026-02-30)\n")
        @test_throws ArgumentError ReleaseMetadata.check(dir)
        set_metadata(replace(dated, "2026-10-19" => "2024-02-29"),
                     "# Release notes\n\n## 0.2.0 (2024-02-29)\n")
        @test ReleaseMetadata.check(dir).date_released == "2024-02-29"
    end
end

@testset "Release CLI options reject mistakes before dependency loading" begin
    @test ReleaseMetadata.expected_version(String[]) === nothing
    @test ReleaseMetadata.expected_version(["--expected-version=0.1.2"]) == v"0.1.2"
    @test ReleaseMetadata.expected_version(["--strict", "--help"]; allowed_flags=("--strict",)) === nothing
    @test ReleaseMetadata.expected_version(["-h"]) === nothing
    for args in (["--unknown"], ["--strict"], ["--expected-version="],
                 ["--expected-version=invalid"],
                 ["--expected-version=0.1.2", "--expected-version=0.1.2"])
        @test_throws ArgumentError ReleaseMetadata.expected_version(args)
    end
    mktempdir() do environment
        write(joinpath(environment, "Project.toml"), "[deps]\n")
        depot = mktempdir(environment)
        empty_path = mktempdir(environment)
        withenv("JULIA_DEPOT_PATH" => depot, "JULIA_LOAD_PATH" => "@:@stdlib",
                "JULIA_PKG_OFFLINE" => "true", "PATH" => empty_path) do
            for name in ("check_release.jl", "pre_registration_gate.jl",
                         "print_registration_handoff.jl", "registration_handoff.jl",
                         "platform_smoke.jl", "distribution_archive_smoke.jl",
                         "public_language_gate.jl", "runtime_public_language_gate.jl", "release_metadata.jl")
                script = joinpath(@__DIR__, "..", "scripts", name)
                command = `$(Base.julia_cmd()) --startup-file=no --history-file=no --compiled-modules=no --project=$environment $script`
                output = read(`$command --help`, String)
                canonical = name == "registration_handoff.jl" ? "print_registration_handoff.jl" :
                    name == "pre_registration_gate.jl" ? "check_release.jl" : name
                @test occursin("Usage:", output)
                @test occursin(canonical, output)
                out, err = IOBuffer(), IOBuffer()
                process = run(pipeline(ignorestatus(`$command --unknown`); stdout=out, stderr=err))
                @test process.exitcode != 0
                @test occursin("unknown argument", String(take!(err)))
                @test isempty(take!(out))
            end
        end
        @test !isfile(joinpath(environment, "Manifest.toml"))
        @test !isdir(joinpath(depot, "registries"))
        @test !isdir(joinpath(depot, "packages"))
    end
end

@testset "A handoff identifies its own checkout and retains strict checks" begin
    mktempdir() do directory
        withenv("PATH" => directory) do
            @test !ReleaseMetadata.repository_context(directory).available
            @test_throws ErrorException ReleaseMetadata.repository_context(directory; strict=true)
        end
        if Sys.which("git") !== nothing
            hooks = joinpath(directory, "empty-hooks")
            mkpath(hooks)
            git(args...) = run(pipeline(`git -C $directory -c core.hooksPath=$hooks $args`;
                stdout=devnull, stderr=devnull))
            git("init", "--quiet")
            git("symbolic-ref", "HEAD", "refs/heads/main")
            git("-c", "user.name=Release test", "-c", "user.email=release@example.invalid",
                "-c", "commit.gpgsign=false", "commit", "--allow-empty", "--quiet", "-m", "fixture")
            context = ReleaseMetadata.repository_context(directory; strict=true)
            @test context.available && context.branch == "main" && !context.dirty
            @test context.commit == readchomp(`git -C $directory rev-parse HEAD`)
            nested = mktempdir(directory)
            @test !ReleaseMetadata.repository_context(nested).available
            @test_throws ErrorException ReleaseMetadata.repository_context(nested; strict=true)
            write(joinpath(directory, "untracked.txt"), "not part of the release\n")
            @test ReleaseMetadata.repository_context(directory).dirty
            @test_throws ErrorException ReleaseMetadata.repository_context(directory; strict=true)
            rm(joinpath(directory, "untracked.txt"))
            git("checkout", "--quiet", "-b", "feature")
            @test ReleaseMetadata.repository_context(directory).branch == "feature"
            @test_throws ErrorException ReleaseMetadata.repository_context(directory; strict=true)
        end
    end
end

end
