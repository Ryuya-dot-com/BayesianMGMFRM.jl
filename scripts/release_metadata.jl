module ReleaseMetadata

using Dates
using TOML

function expected_version(args; allowed_flags = ())
    version = nothing
    for arg in args
        arg in ("--help", "-h") && continue
        arg in allowed_flags && continue
        startswith(arg, "--expected-version=") ||
            throw(ArgumentError("unknown argument: $arg"))
        version === nothing || throw(ArgumentError("--expected-version may be supplied only once"))
        value = split(arg, '='; limit = 2)[2]
        isempty(value) && throw(ArgumentError("--expected-version requires a version"))
        version = VersionNumber(value)
    end
    return version
end

function repository_context(root; strict = false)
    function unavailable()
        strict && error("strict handoff requires a Git checkout rooted at this source directory")
        return (; available = false, branch = nothing, commit = nothing, dirty = nothing)
    end
    read_git(args) = readchomp(pipeline(Cmd(`git $args`; dir = root); stderr = devnull))
    context = try
        top = read_git(["rev-parse", "--show-toplevel"])
        # A nested snapshot must not inherit its ancestor checkout's identity.
        realpath(top) == realpath(root) || return unavailable()
        branch = read_git(["branch", "--show-current"])
        commit = read_git(["rev-parse", "HEAD"])
        dirty = !isempty(read_git(["status", "--porcelain"]))
        (; available = true, branch, commit, dirty)
    catch err
        err isa Base.IOError || err isa Base.ProcessFailedException || rethrow()
        return unavailable()
    end
    if strict
        context.branch == "main" || error("strict handoff must run from main, got $(context.branch)")
        !context.dirty || error("worktree changes are present")
    end
    return context
end

# Check the repository's plain, top-level scalar fields, not the full CFF schema.
function cff_scalar(text, key; required = true)
    fields = collect(eachmatch(Regex("(?m)^" * key * ":[^\\r\\n]*"), text))
    if isempty(fields) && !required
        return nothing
    end
    length(fields) == 1 || error("CITATION.cff must have exactly one top-level $key field")
    value = strip(split(only(fields).match, ':'; limit = 2)[2])
    scalar = match(r"^(?:\"([^\"]+)\"|'([^']+)'|([A-Za-z0-9.+-]+))(?:\s+#.*)?$", value)
    scalar === nothing && error("CITATION.cff $key must be a plain or quoted scalar on one line")
    return only(filter(!isnothing, scalar.captures))
end

function check(root = dirname(@__DIR__))
    version = VersionNumber(TOML.parsefile(joinpath(root, "Project.toml"))["version"])
    citation = read(joinpath(root, "CITATION.cff"), String)
    citation_version = VersionNumber(cff_scalar(citation, "version"))
    citation_version == version || error(
        "CITATION.cff version $citation_version does not match Project.toml version $version")

    news = read(joinpath(root, "NEWS.md"), String)
    heading = match(r"(?m)^## ([^\r\n]+)", news)
    heading === nothing && error("NEWS.md is missing its latest version heading")
    release = match(r"^([^ ]+) \((unreleased|\d{4}-\d{2}-\d{2})\)$", heading.captures[1])
    release === nothing && error("Latest NEWS.md heading must be ## VERSION (unreleased or YYYY-MM-DD)")
    VersionNumber(release.captures[1]) == version || error(
        "Latest NEWS.md version does not match Project.toml version $version")

    date = cff_scalar(citation, "date-released"; required = false)
    unreleased = release.captures[2] == "unreleased"
    if unreleased
        date === nothing || error("Unreleased NEWS.md must not carry a CITATION.cff date-released")
    else
        date == release.captures[2] || error("CITATION.cff date-released must match the latest NEWS.md date")
        Date(date, dateformat"yyyy-mm-dd") # Reject impossible calendar dates too.
    end
    return (; version, unreleased, date_released = date)
end

end

if abspath(PROGRAM_FILE) == @__FILE__
    for arg in ARGS
        arg in ("-h", "--help") || throw(ArgumentError("unknown argument: $arg"))
    end
    if isempty(ARGS)
        result = ReleaseMetadata.check()
        status = result.unreleased ? "unreleased" : result.date_released
        println("Release metadata consistent: $(result.version) ($status). This does not verify publication.")
    else
        println("Usage: julia --startup-file=no scripts/release_metadata.jl")
        println("Check Project.toml, CITATION.cff and NEWS.md using standard libraries only.")
    end
end
