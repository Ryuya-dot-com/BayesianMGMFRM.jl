module BayesianMGMFRM

export evidence_metadata

include("evidence_metadata.jl")

# Validation target used by the analytic-gradient test suite.
# Public model-fitting APIs will be introduced with the data/spec layer.
include("faithful_fastlogp.jl")

end
