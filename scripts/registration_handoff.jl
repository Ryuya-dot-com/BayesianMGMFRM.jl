#!/usr/bin/env julia

# Print the manual Registrator trigger comment for the current release commit.
# This script intentionally does not call GitHub, Registrator, or General.

using Pkg

const ROOT = abspath(normpath(joinpath(@__DIR__, "..")))
Pkg.activate(ROOT; io = devnull)
Pkg.instantiate(; io = devnull)

using BayesianMGMFRM
using TOML

const STRICT = "--strict" in ARGS

function read_cmd(cmd::Cmd)
    return strip(readchomp(Cmd(cmd; dir = ROOT)))
end

function project_file()
    path = joinpath(ROOT, "Project.toml")
    isfile(path) || error("Project.toml not found at $path")
    return TOML.parsefile(path)
end

function assert_release_boundary()
    scope = release_scope_summary(; include_evidence = true)
    summary = scope.summary
    summary.next_gate == :manual_publication_or_registration_by_user_only ||
        error("unexpected next release gate: $(summary.next_gate)")
    summary.publication_or_registration_action == false ||
        error("release scope already records a publication or registration action")
    summary.general_registration_manual_only == true ||
        error("release scope no longer records General registration as manual-only")
    return summary
end

function assert_project_metadata(project)
    name = String(project["name"])
    version = VersionNumber(String(project["version"]))
    name == "BayesianMGMFRM" || error("unexpected package name: $name")
    version == v"0.1.0" || error("unexpected registration version: $version")
    return (; name, version)
end

function emit_handoff()
    project = project_file()
    metadata = assert_project_metadata(project)
    summary = assert_release_boundary()
    branch = read_cmd(`git branch --show-current`)
    commit = read_cmd(`git rev-parse HEAD`)
    status = read_cmd(`git status --porcelain --untracked-files=no`)

    if STRICT
        branch == "main" || error("strict handoff must run from main, got $branch")
        isempty(status) || error("tracked worktree changes are present:\n$status")
    end

    println("Registration handoff")
    println("  package: ", metadata.name)
    println("  version: ", metadata.version)
    println("  branch: ", isempty(branch) ? "(detached)" : branch)
    println("  commit: ", commit)
    println("  strict: ", STRICT)
    println("  next_gate: ", summary.next_gate)
    if !isempty(status)
        println("  tracked_changes: present")
    end

    println()
    println("Manual Registrator comment:")
    println()
    println("@JuliaRegistrator register")
    println()
    println("Release notes:")
    println()
    println("Initial 0.1.0 release of BayesianMGMFRM.jl. This release provides a")
    println("conservative Bayesian many-facet Rasch workflow scaffold covering")
    println("long-format data validation, design inspection, minimal MFRM/RSM/PCM")
    println("fitting, and guarded scalar GMFRM / fixed-Q confirmatory MGMFRM")
    println("experiments. Broader GMFRM/MGMFRM fitting, fitted DFF effects,")
    println("model-weight or sparse-superiority claims, manuscript claims, and")
    println("publication actions remain out of scope.")
    return nothing
end

emit_handoff()
