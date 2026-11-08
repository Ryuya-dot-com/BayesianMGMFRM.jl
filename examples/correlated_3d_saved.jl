# Run in the fit's original source/environment, passing its trusted native path.
# This example performs no fitting, generation or automatic recovery.
using BayesianMGMFRM
length(ARGS)==1 || error("Pass one trusted Correlated3D native fit path")
C=BayesianMGMFRM.Experimental.Correlated3D
result=C.load_result(only(ARGS))
report=C.report(result)
println(report.result.posterior)
println(C.probabilities(result;observation=1).result.posterior)
