#!/usr/bin/env julia

# Print the manual registry-update trigger comment for the current release.
# This script intentionally does not call GitHub, Registrator, or General.

include(joinpath(@__DIR__, "release_metadata.jl"))
const HANDOFF_HELP = """
Usage: julia --startup-file=no --project=. scripts/print_registration_handoff.jl [OPTIONS]

Prints a draft of manual registration instructions from validated package
metadata. Loads this source and checks its manual-only release boundary using
installed dependencies. No project activation, dependency installation, fitting,
GitHub request, publication or registration is performed.

Source archives and nested snapshots have no Git identity of their own.
--strict requires a clean main checkout rooted at this source directory.

Options:
  --expected-version=VERSION  Require this package version.
  --strict                   Require a clean main checkout of this source.
  -h, --help                 Print help without activating project dependencies.
"""
const EXPECTED_VERSION = ReleaseMetadata.expected_version(ARGS; allowed_flags = ("--strict",))
if any(arg -> arg in ("-h", "--help"), ARGS)
    print(HANDOFF_HELP)
    exit(0)
end

const ROOT = abspath(normpath(joinpath(@__DIR__, "..")))
# Honor the caller's dependency environment; verify the loaded source below.

using BayesianMGMFRM
using TOML

realpath(pathof(BayesianMGMFRM)) == realpath(joinpath(ROOT, "src", "BayesianMGMFRM.jl")) ||
    error("the loaded package does not match this source tree")

const STRICT = "--strict" in ARGS


function project_file()
    path = joinpath(ROOT, "Project.toml")
    isfile(path) || error("Project.toml not found at $path")
    return TOML.parsefile(path)
end

function assert_release_boundary()
    scope = BayesianMGMFRM.ValidationSuite.release_scope_summary(; include_evidence = true)
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
    version >= v"0.1.0" || error("release version must be at least 0.1.0, got $version")
    if EXPECTED_VERSION !== nothing
        version == EXPECTED_VERSION ||
            error("expected release version $(EXPECTED_VERSION), got $version")
    end
    return (; name, version)
end

function emit_handoff()
    project = project_file()
    metadata = assert_project_metadata(project)
    ReleaseMetadata.check(ROOT)
    assert_release_boundary()
    context = ReleaseMetadata.repository_context(ROOT; strict = STRICT)

    println("Registry-update handoff")
    println("  package: ", metadata.name)
    println("  version: ", metadata.version)
    println("  branch: ", !context.available ? "(unavailable for this source tree)" :
        isempty(context.branch) ? "(detached)" : context.branch)
    println("  commit: ", context.available ? context.commit : "(unavailable for this source tree)")
    println("  strict: ", STRICT)
    if context.dirty === true
        println("  worktree_changes: present")
    end

    println()
    println("Manual Registrator comment:")
    println()
    println("@JuliaRegistrator register")
    println()
    println("Release notes:")
    println()
    println("Use NEWS.md for version $(metadata.version) and docs/src/scope.md for supported combinations.")
    println("This draft does not certify release readiness or change publication authority.")
    return nothing
end

emit_handoff()
