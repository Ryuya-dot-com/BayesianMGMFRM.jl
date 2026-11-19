# Run in the fit's original source/environment, passing its trusted native path.
# This example performs no fitting, generation or automatic recovery.
if abspath(PROGRAM_FILE)==abspath(@__FILE__) && (isempty(ARGS) || ARGS==["--help"])
    println("Usage: julia --project=. examples/correlated_3d_saved.jl FIT.jls")
    println("Use an existing trusted Correlated3D native fit path in its original environment.")
    exit(0)
end
using BayesianMGMFRM
length(ARGS)==1 || error("Pass one trusted Correlated3D native fit path")
C=BayesianMGMFRM.Experimental.Correlated3D
result=C.load_result(only(ARGS))
report=C.report(result)
println(report.result.posterior)
println(C.probabilities(result;observation=1).result.posterior)
