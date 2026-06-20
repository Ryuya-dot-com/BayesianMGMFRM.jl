using Documenter
using BayesianMGMFRM

makedocs(;
    sitename = "BayesianMGMFRM.jl",
    modules = [BayesianMGMFRM],
    pages = [
        "Home" => "index.md",
        "Data Validation" => "data-validation.md",
        "Model Equations" => "model-equations.md",
        "Bayesian Workflow" => "bayesian-workflow.md",
        "Bayesian Fitting" => "fitting.md",
        "Examples" => "examples.md",
        "Roadmap and Scope" => "roadmap.md",
        "API" => "api.md",
    ],
    warnonly = [:missing_docs],
)
