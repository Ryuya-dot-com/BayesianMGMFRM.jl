#!/usr/bin/env julia

# Local pre-registration gate for BayesianMGMFRM.jl.
# This is intentionally stricter than ordinary `Pkg.test()` and mirrors the
# checks needed before asking Registrator to publish the first package version.

using Pkg
using TOML

const ROOT = abspath(normpath(joinpath(@__DIR__, "..")))
const JULIA = joinpath(Sys.BINDIR, Base.julia_exename())

const SKIP_TESTS = "--skip-tests" in ARGS
const SKIP_DOCS = "--skip-docs" in ARGS
const SKIP_AQUA = "--skip-aqua" in ARGS

function step(name::AbstractString, f::Function)
    println("\n==> ", name)
    f()
    println("OK: ", name)
end

function run_cmd(cmd::Cmd)
    run(Cmd(cmd; dir = ROOT))
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

    name == "BayesianMGMFRM" || error("unexpected package name: $name")
    root_name == "BayesianMGMFRM.jl" ||
        error("repository directory should be BayesianMGMFRM.jl, got $root_name")
    occursin(r"^[A-Za-z][A-Za-z0-9_]+$", name) ||
        error("package name is not a valid ASCII Julia identifier: $name")
    length(name) >= 5 || error("package name is too short for General registry expectations")
    occursin("julia", lowercase(name)) && error("package name must not contain `julia`")
    endswith(lowercase(name), "jl") && error("package name must not end with `jl`")
    uuid == "1c3fdc16-45de-4463-900f-cd2a5999ffa5" || error("unexpected uuid: $uuid")
    version == v"0.1.0" || error("unexpected initial version: $version")
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
    isfile(joinpath(ROOT, "docs", "make.jl")) || error("docs/make.jl is missing")
    isfile(joinpath(ROOT, "scripts", "generate_validation_plan.jl")) ||
        error("scripts/generate_validation_plan.jl is missing")
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

function run_minimal_example()
    run_with_developed_package("""include($(repr(joinpath(ROOT, "examples", "minimal.jl"))))""")
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

function public_wording_check()
    public_files = each_source_file(["README.md", "NEWS.md", "src", "docs/src", "examples"])
    public_audit_hits = String[]
    for path in public_files
        for (line_no, line) in enumerate(eachline(path))
            occursin(r"\b[Aa]udit\b", line) || continue
            push!(public_audit_hits, "$(relpath(path, ROOT)):$line_no:$line")
        end
    end
    isempty(public_audit_hits) ||
        error("public wording still contains audit terminology:\n" * join(public_audit_hits, "\n"))

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

step("Project metadata and registration shape", metadata_check)
step("Clean temporary-environment import", clean_import_check)
step("Instantiate package in temporary environment", instantiate_project)
if !SKIP_TESTS
    step("Pkg.test()", run_package_tests)
end
step("Minimal example", run_minimal_example)
if !SKIP_DOCS
    step("Documenter build", build_docs)
end
if !SKIP_AQUA
    step("Aqua package hygiene", run_aqua)
end
step("git diff --check", git_diff_check)
step("Public wording and skipped-test scan", public_wording_check)

println("\nPre-registration gate passed.")
