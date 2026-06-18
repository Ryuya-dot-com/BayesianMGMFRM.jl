using Documenter
using BayesianMGMFRM

makedocs(;
    sitename = "BayesianMGMFRM.jl",
    modules = [BayesianMGMFRM],
    pages = [
        "Home" => "index.md",
        "Data Validation" => "data-validation.md",
        "API" => "api.md",
    ],
    warnonly = [:missing_docs],
)
