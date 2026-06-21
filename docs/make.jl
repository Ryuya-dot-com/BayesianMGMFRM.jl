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
        "API" => [
            "Overview" => "api.md",
            "Data and Design" => "api-data-design.md",
            "Fitting and Artifacts" => "api-fitting-artifacts.md",
            "Workflow and Diagnostics" => "api-workflow-diagnostics.md",
            "Validation and Evidence" => "api-validation-evidence.md",
        ],
    ],
    warnonly = [:missing_docs],
)
