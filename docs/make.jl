using Documenter
using BayesianMGMFRM

makedocs(;
    sitename = "BayesianMGMFRM.jl",
    modules = [BayesianMGMFRM, BayesianMGMFRM.Experimental],
    checkdocs = :exports,
    build = get(ENV, "BAYESIANMGMFRM_DOCS_BUILD", "build"),
    format = Documenter.HTML(;
        size_threshold = 100 * 2^10,
        size_threshold_warn = nothing,
    ),
    pagesonly = true,
    pages = [
        "Home" => "index.md",
        "Data Validation" => "data-validation.md",
        "Model Equations" => "model-equations.md",
        "Bayesian Workflow" => "bayesian-workflow.md",
        "Bayesian Fitting" => "fitting.md",
        "Experimental Generalized Models" => "experimental.md",
        "Examples" => "examples.md",
        "Migrating from FACETS and ConQuest" => "migration-facets-conquest.md",
        "Scope and Releases" => "scope.md",
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
