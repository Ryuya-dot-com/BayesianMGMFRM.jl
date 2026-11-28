# Standard entry point; the v0.2 implementation is shared with existing callers.
include(joinpath(@__DIR__, "first_analysis_v02.jl"))
const FirstMFRMAnalysis = FirstMFRMAnalysisV02

if abspath(PROGRAM_FILE) == @__FILE__
    FirstMFRMAnalysis.main(ARGS)
end
