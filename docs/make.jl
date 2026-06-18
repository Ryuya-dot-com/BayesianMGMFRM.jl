using Documenter
using BayesianMGMFRM

makedocs(;
    sitename = "BayesianMGMFRM.jl",
    modules = [BayesianMGMFRM],
    pages = [
        "Home" => "index.md",
        "Data Validation" => "data-validation.md",
        "Bayesian Fitting" => "fitting.md",
        "API" => "api.md",
    ],
    warnonly = [:missing_docs],
)
