# Shared by the full runner and the standalone local-dependence checks.
function test_flag(name::AbstractString; default::Bool = false)
    value = lowercase(strip(get(ENV, name, string(default))))
    value in ("1", "true", "yes", "on") && return true
    value in ("", "0", "false", "no", "off") && return false
    throw(ArgumentError(
        "$name must be one of 1/true/yes/on or 0/false/no/off; got $(repr(value))",
    ))
end

const RUN_RESEARCH_EVIDENCE_TESTS =
    test_flag("BAYESIANMGMFRM_RESEARCH_EVIDENCE_TESTS")

const TEST_SHARDS = (
    :core, :fitting_core, :fitting_reports,
    :local_dependence_core, :local_dependence_integrity, :generalized,
)
const TEST_GROUPS = (TEST_SHARDS..., :fitting, :local_dependence)

function selected_test_group(value::AbstractString = get(
        ENV, "BAYESIANMGMFRM_TEST_GROUP", "all");
        research_evidence::Bool = RUN_RESEARCH_EVIDENCE_TESTS)
    value = lowercase(strip(value))
    group = value in ("", "all") ? :all : Symbol(value)
    group === :all || group in TEST_GROUPS || throw(ArgumentError(
        "BAYESIANMGMFRM_TEST_GROUP must be all or one of " *
        "$(join(TEST_GROUPS, ", ")); got $(repr(value))",
    ))
    research_evidence && group !== :all && throw(ArgumentError(
        "BAYESIANMGMFRM_RESEARCH_EVIDENCE_TESTS=true requires " *
        "BAYESIANMGMFRM_TEST_GROUP=all",
    ))
    return group
end

const ACTIVE_TEST_GROUP = selected_test_group()

function test_group_enabled(group::Symbol, active::Symbol = ACTIVE_TEST_GROUP)
    group in TEST_GROUPS || throw(ArgumentError("unknown test group: $group"))
    return active === :all || active === group ||
        (active === :fitting && group in (:fitting_core, :fitting_reports)) ||
        (active === :local_dependence &&
            group in (:local_dependence_core, :local_dependence_integrity))
end
