using BayesianMGMFRM

meta = evidence_metadata(; include_packages = false)

println("BayesianMGMFRM loaded")
println("Julia version: ", meta["software"]["julia"]["version"])
println("CPU: ", meta["hardware"]["cpu_model"])
