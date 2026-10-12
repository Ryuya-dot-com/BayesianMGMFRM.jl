using BayesianMGMFRM, Serialization

"""
    saved_recovery_replications(paths; kwargs...)

Reload serialized `recovery_evaluation` records and summarize a predeclared
fixed-truth scenario. Supply the complete planned roster even if files are
missing or fits failed. Independent datasets and their generation must be
documented separately; this example does not generate data or run fits.
"""
function saved_recovery_replications(paths; kwargs...)
    return BayesianMGMFRM.recovery_replications(deserialize.(paths); kwargs...)
end
