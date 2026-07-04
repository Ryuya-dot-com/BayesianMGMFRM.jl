using Documenter
using BayesianMGMFRM

makedocs(;
    sitename = "BayesianMGMFRM.jl",
    modules = [BayesianMGMFRM],
    format = Documenter.HTML(;
        size_threshold = 100 * 2^10,
        size_threshold_warn = nothing,
    ),
    pages = [
        "Home" => "index.md",
        "Data Validation" => "data-validation.md",
        "Model Equations" => "model-equations.md",
        "Bayesian Workflow" => "bayesian-workflow.md",
        "Bayesian Fitting" => "fitting.md",
        "Examples" => "examples.md",
        "Registration Handoff" => "registration.md",
        "Roadmap and Scope" => "roadmap.md",
        "MGMFRM Research Roadmap" => "mgmfrm-research-roadmap.md",
        "v0.1.1 Implementation Checklist" => "v0.1.1-implementation-checklist.md",
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
