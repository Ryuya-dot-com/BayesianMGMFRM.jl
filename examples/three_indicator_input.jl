# Inspect an existing labelled input. Including this file performs no analysis.
using BayesianMGMFRM

function three_indicator_input(path;expected_sha256)
    BayesianMGMFRM.Experimental.ThreeIndicator.inspect_input(path;expected_sha256)
end
