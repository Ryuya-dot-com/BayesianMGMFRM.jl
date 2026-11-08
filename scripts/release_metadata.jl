module ReleaseMetadata

using Dates
using TOML

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
    result = ReleaseMetadata.check()
    status = result.unreleased ? "unreleased" : result.date_released
    println("Release metadata consistent: $(result.version) ($status). This does not verify publication.")
end
