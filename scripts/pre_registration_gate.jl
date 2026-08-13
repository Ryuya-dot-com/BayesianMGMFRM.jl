#!/usr/bin/env julia

# Release-verification gate for BayesianMGMFRM.jl.
# The historical filename is retained for compatibility with existing local
# workflows. This gate is intentionally stricter than ordinary `Pkg.test()`.

using Pkg
using TOML

include(joinpath(@__DIR__, "public_language_gate.jl"))
using .PublicLanguageGate

const ROOT = abspath(normpath(joinpath(@__DIR__, "..")))
const JULIA = joinpath(Sys.BINDIR, Base.julia_exename())

const SKIP_TESTS = "--skip-tests" in ARGS
const SKIP_DOCS = "--skip-docs" in ARGS
const SKIP_AQUA = "--skip-aqua" in ARGS
const SKIP_PUBLIC_LANGUAGE =
    "--skip-public-language" in ARGS || "--skip-public-wording" in ARGS
const EXPECTED_VERSION = let
    values = [split(arg, "="; limit = 2)[2]
              for arg in ARGS if startswith(arg, "--expected-version=")]
    length(values) <= 1 || error("--expected-version may be supplied only once")
    isempty(values) ? nothing : VersionNumber(only(values))
end

function step(name::AbstractString, f::Function)
    println("\n==> ", name)
    f()
    println("OK: ", name)
end

function run_cmd(cmd::Cmd)
    run(Cmd(cmd; dir = ROOT))
end

function capture_cmd(cmd::Cmd)
    stdout_buffer = IOBuffer()
    stderr_buffer = IOBuffer()
    failure = nothing
    try
        run(pipeline(Cmd(cmd; dir = ROOT);
            stdout = stdout_buffer,
            stderr = stderr_buffer))
    catch err
        failure = err
    end
    return (;
        passed = failure === nothing,
        stdout = String(take!(stdout_buffer)),
        stderr = String(take!(stderr_buffer)),
        failure,
    )
end

function read_cmd(cmd::Cmd)
    return readchomp(Cmd(cmd; dir = ROOT))
end

function run_julia(code::AbstractString; project = nothing)
    if project === nothing
        run_cmd(`$JULIA --startup-file=no -e $code`)
    else
        run_cmd(`$JULIA --startup-file=no --project=$project -e $code`)
    end
end

function run_with_developed_package(code::AbstractString)
    full_code = """
        using Pkg
        Pkg.activate(; temp = true)
        Pkg.develop(PackageSpec(path = $(repr(ROOT))))
        Pkg.instantiate()
        $code
        """
    run_julia(full_code)
    return nothing
end

function project_file()
    path = joinpath(ROOT, "Project.toml")
    isfile(path) || error("Project.toml not found at $path")
    return TOML.parsefile(path)
end

function assert_present(project, key)
    haskey(project, key) || error("Project.toml is missing key `$key`")
    value = project[key]
    if value isa AbstractString
        isempty(strip(value)) && error("Project.toml key `$key` is empty")
    elseif value isa AbstractVector
        isempty(value) && error("Project.toml key `$key` is empty")
    end
    return value
end

function metadata_check()
    project = project_file()
    name = assert_present(project, "name")
    uuid = assert_present(project, "uuid")
    authors = assert_present(project, "authors")
    version = VersionNumber(assert_present(project, "version"))
    root_name = last(splitpath(ROOT))
    origin_url = try
        read_cmd(`git config --get remote.origin.url`)
    catch err
        error("could not read git remote.origin.url: $err")
    end
    origin_repo_path = replace(strip(origin_url), r"\.git$" => "")

    name == "BayesianMGMFRM" || error("unexpected package name: $name")
    root_name == "BayesianMGMFRM.jl" ||
        error("repository directory should be BayesianMGMFRM.jl, got $root_name")
    Base.isidentifier(name) || error("package name is not a valid Julia identifier: $name")
    occursin(r"^[A-Z][A-Za-z0-9]+$", name) ||
        error("package name should start with uppercase and contain only ASCII alphanumeric characters: $name")
    any(islowercase, name) || error("package name should contain at least one lowercase character")
    length(name) >= 5 || error("package name is too short for General registry expectations")
    occursin("julia", lowercase(name)) && error("package name must not contain `julia`")
    startswith(name, "Ju") && error("package name must not start with `Ju`")
    endswith(lowercase(name), "jl") && error("package name must not end with `jl`")
    (endswith(origin_repo_path, "/BayesianMGMFRM.jl") ||
        endswith(origin_repo_path, ":BayesianMGMFRM.jl")) ||
        error("origin URL should resolve to repository path BayesianMGMFRM.jl, got $origin_url")
    uuid == "1c3fdc16-45de-4463-900f-cd2a5999ffa5" || error("unexpected uuid: $uuid")
    version >= v"0.1.0" || error("release version must be at least 0.1.0, got $version")
    if EXPECTED_VERSION !== nothing
        version == EXPECTED_VERSION ||
            error("expected release version $(EXPECTED_VERSION), got $version")
    end
    all(!isempty(strip(String(author))) for author in authors) ||
        error("authors must be non-empty strings")

    deps = get(project, "deps", Dict{String,Any}())
    extras = get(project, "extras", Dict{String,Any}())
    compat = get(project, "compat", Dict{String,Any}())
    haskey(compat, "julia") || error("[compat] must include julia")

    missing_dep_compat = setdiff(collect(keys(deps)), collect(keys(compat)))
    isempty(missing_dep_compat) ||
        error("[compat] is missing entries for [deps]: $(sort(missing_dep_compat))")
    missing_extra_compat = setdiff(collect(keys(extras)), collect(keys(compat)))
    isempty(missing_extra_compat) ||
        error("[compat] is missing entries for [extras]: $(sort(missing_extra_compat))")

    for (dep, bound) in compat
        text = strip(String(bound))
        isempty(text) && error("[compat] entry for $dep is empty")
        occursin("*", text) && error("[compat] entry for $dep is unbounded: $text")
    end

    read(joinpath(ROOT, "LICENSE"), String) |> text -> occursin("MIT License", text) ||
        error("LICENSE must contain MIT License")
    isfile(joinpath(ROOT, "README.md")) || error("README.md is missing")
    isfile(joinpath(ROOT, "NEWS.md")) || error("NEWS.md is missing")
    isfile(joinpath(ROOT, "examples", "minimal.jl")) || error("examples/minimal.jl is missing")
    isfile(joinpath(ROOT, "examples", "guarded_gmfrm.jl")) ||
        error("examples/guarded_gmfrm.jl is missing")
    isfile(joinpath(ROOT, "examples", "guarded_mgmfrm.jl")) ||
        error("examples/guarded_mgmfrm.jl is missing")
    isfile(joinpath(ROOT, "docs", "make.jl")) || error("docs/make.jl is missing")
    isfile(joinpath(ROOT, "scripts", "generate_validation_plan.jl")) ||
        error("scripts/generate_validation_plan.jl is missing")
    isfile(joinpath(ROOT, "scripts", "registration_handoff.jl")) ||
        error("scripts/registration_handoff.jl is missing")
    return nothing
end

function clean_import_check()
    run_with_developed_package("import BayesianMGMFRM")
    return nothing
end

function instantiate_project()
    run_with_developed_package("")
    return nothing
end

function run_package_tests()
    run_with_developed_package("""Pkg.test("BayesianMGMFRM")""")
    return nothing
end

function public_example_paths()
    paths = String[]
    for path in PublicLanguageGate.public_surface_paths(ROOT)
        relative = relpath(path, ROOT)
        parts = splitpath(relative)
        isempty(parts) && continue
        first(parts) == "examples" || continue
        push!(paths, path)
    end
    return sort(paths)
end

function _preserve_captured_example_output(relative::String, captured)
    if !isempty(captured.stdout)
        println("\n--- example stdout: $relative ---")
        print(captured.stdout)
        endswith(captured.stdout, "\n") || println()
    end
    if !isempty(captured.stderr)
        println(stderr, "\n--- example stderr: $relative ---")
        print(stderr, captured.stderr)
        endswith(captured.stderr, "\n") || println(stderr)
    end
    return nothing
end

function run_public_examples()
    failures = String[]
    for path in public_example_paths()
        relative = relpath(path, ROOT)
        captured = capture_cmd(
            `$JULIA --startup-file=no --project=$ROOT $path`)
        _preserve_captured_example_output(relative, captured)
        outputs = Pair{String,String}[]
        isempty(captured.stdout) ||
            push!(outputs, "example:$relative:stdout" => captured.stdout)
        isempty(captured.stderr) ||
            push!(outputs, "example:$relative:stderr" => captured.stderr)
        violations = PublicLanguageGate.runtime_language_violations(outputs)
        if !isempty(violations)
            details = [
                "[$(violation.rule)] $(violation.surface):$(violation.line): " *
                violation.excerpt
                for violation in violations
            ]
            push!(failures,
                "$relative emitted restricted public language:\n" *
                join(details, "\n"))
        end
        captured.passed || push!(failures,
            "$relative failed: $(sprint(showerror, captured.failure))")
    end
    isempty(failures) || error(
        "public example verification failed:\n" * join(failures, "\n"))
    return nothing
end

function run_registration_handoff()
    run_cmd(`$JULIA --startup-file=no --project=$ROOT scripts/registration_handoff.jl`)
    return nothing
end

function build_docs()
    make_path = joinpath(ROOT, "docs", "make.jl")
    code = """
        Pkg.add(PackageSpec(name = "Documenter", version = "1"))
        include($(repr(make_path)))
        """
    run_with_developed_package(code)
    return nothing
end

function run_aqua()
    code = """
        Pkg.add(PackageSpec(name = "Aqua", version = "0.8"))
        using BayesianMGMFRM
        using Aqua
        Aqua.test_all(BayesianMGMFRM; ambiguities = false)
        """
    run_with_developed_package(code)
    return nothing
end

function git_diff_check()
    run_cmd(`git diff --check`)
    return nothing
end

function each_source_file(paths)
    out = String[]
    for rel in paths
        path = joinpath(ROOT, rel)
        if isfile(path)
            push!(out, path)
        elseif isdir(path)
            for (dir, _, files) in walkdir(path)
                for file in files
                    ext = splitext(file)[2]
                    ext in (".jl", ".md") || continue
                    push!(out, joinpath(dir, file))
                end
            end
        end
    end
    return sort(out)
end

function public_language_check()
    PublicLanguageGate.assert_public_language(ROOT)
    !SKIP_DOCS && PublicLanguageGate.assert_rendered_public_language(ROOT)
    return nothing
end

function runtime_public_language_check()
    run_cmd(`$JULIA --startup-file=no --project=$ROOT scripts/runtime_public_language_gate.jl`)
    return nothing
end

function skipped_test_check()
    test_files = each_source_file(["test"])
    skipped_hits = String[]
    for path in test_files
        for (line_no, line) in enumerate(eachline(path))
            if occursin("@test_skip", line) || occursin("@test_broken", line)
                push!(skipped_hits, "$(relpath(path, ROOT)):$line_no:$line")
            end
        end
    end
    isempty(skipped_hits) ||
        error("test suite contains skipped or broken tests:\n" * join(skipped_hits, "\n"))
    return nothing
end

step("Project metadata and registry shape", metadata_check)
step("Clean temporary-environment import", clean_import_check)
step("Instantiate package in temporary environment", instantiate_project)
step("Registration handoff message", run_registration_handoff)
if !SKIP_TESTS
    step("Pkg.test()", run_package_tests)
end
step("Public examples", run_public_examples)
if !SKIP_DOCS
    step("Documenter build", build_docs)
end
if !SKIP_AQUA
    step("Aqua package hygiene", run_aqua)
end
step("git diff --check", git_diff_check)
if !SKIP_PUBLIC_LANGUAGE
    step("Public language gate", public_language_check)
    step("Runtime public language gate", runtime_public_language_check)
end
step("Skipped-test scan", skipped_test_check)

println("\nRelease-verification gate passed.")
