using Documenter
using BayesianMGMFRM

const ROOT_API_REFERENCE_PAGES = (
    "api-data-design.md",
    "api-fitting-artifacts.md",
    "api-workflow-diagnostics.md",
    "api-saved-reporting.md",
    "api-validation-evidence.md",
    "prior-sensitivity.md",
)

function documented_root_bindings()
    documented = Set{Symbol}()
    docs_block = r"(?ms)^```@docs[ \t]*\n(.*?)^```[ \t]*$"
    binding = r"^(?:BayesianMGMFRM\.)?([A-Za-z_][A-Za-z0-9_!?]*)"
    for page in ROOT_API_REFERENCE_PAGES
        source = read(joinpath(@__DIR__, "src", page), String)
        for block in eachmatch(docs_block, source)
            for line in eachline(IOBuffer(block.captures[1]))
                match_result = match(binding, strip(line))
                match_result === nothing && continue
                push!(documented, Symbol(match_result.captures[1]))
            end
        end
    end
    return documented
end

function check_root_api_documentation()
    contract = BayesianMGMFRM._root_api_contract()
    required = union(Set(contract.stable), Set(contract.compatibility))
    missing = sort!(collect(setdiff(required, documented_root_bindings()));
        by = String)
    isempty(missing) || error(
        "stable/compatibility root bindings missing from the API reference: " *
        join(missing, ", "),
    )
    return nothing
end

check_root_api_documentation()

makedocs(;
    sitename = "BayesianMGMFRM.jl",
    modules = [BayesianMGMFRM, BayesianMGMFRM.Experimental],
    remotes = nothing,
    checkdocs = :exports,
    build = get(ENV, "BAYESIANMGMFRM_DOCS_BUILD", "build"),
    format = Documenter.HTML(;
        edit_link = nothing,
        repolink = "https://github.com/Ryuya-dot-com/BayesianMGMFRM.jl",
        # Shared navigation counts toward page size; retain an early warning.
        size_threshold = 128 * 2^10,
        size_threshold_warn = 100 * 2^10,
    ),
    pagesonly = true,
    pages = [
        "Home" => "index.md",
        "Getting Started and Workflow" => [
            "Getting Started" => "learning-guide.md",
            "Bayesian Workflow" => "bayesian-workflow.md",
            "Examples" => "examples.md",
            "Data Validation" => "data-validation.md",
            "Bayesian Fitting" => "fitting.md",
            "Reading Results and Comparing Models" => "interpreting-results.md",
            "Visualization Gallery" => "visualization-gallery.md",
            "Migrating from FACETS and ConQuest" => "migration-facets-conquest.md",
        ],
        "Model Guides and Theory" => [
            "How Rating Models Work" => "rating-model-theory.md",
            "Model Equations" => "model-equations.md",
            "Expected Scores and Information" => "score-information.md",
            "Prior Sensitivity" => "prior-sensitivity.md",
            "Saved Prediction and Recovery" => "common_prediction_comparison.md",
            "Plan a Rating Study" => "design-planning.md",
        ],
        "Experimental Model Extensions" => [
            "Experimental Models Overview" => "experimental.md",
            "User-Named Additive Facets" => "additive-facets.md",
            "Correlations among Three Traits" => "correlated-3d.md",
            "Shared-response Joint Ratings" => "joint-ratings.md",
            "Paired Ordinal Association" => "ordinal-association.md",
            "Star-Factorized Multi-Criterion Association" => "star-association.md",
            "Concurrent Three-Outcome Study" => "concurrent-three-outcome.md",
            "Group Differences in Rater Severity" => "rater-group-effects.md",
            "Criterion Collapse" => "criterion-collapse.md",
            "Rater Drift: Fitting and Comparison" => "rater-drift.md",
        ],
        "Scope, Roadmap and Reproducibility" => [
            "Scope and Releases" => "scope.md",
            "Development Roadmap" => "roadmap.md",
            "Evidence for Model Extensions" => "mgmfrm-research-roadmap.md",
            "Versions and Saved Results" => "registration.md",
            "Getting Help and Contributing" => "contributing.md",
        ],
        "API Reference" => [
            "Overview" => "api.md",
            "Data and Design" => "api-data-design.md",
            "Fitting and Artifacts" => "api-fitting-artifacts.md",
            "Workflow and Diagnostics" => "api-workflow-diagnostics.md",
            "Saving and Reopening Results" => "api-saved-reporting.md",
            "Prediction and Recovery" => "api-prediction-recovery.md",
            "Experimental Models" => "api-experimental.md",
            "Validation and Evidence" => "api-validation-evidence.md",
        ],
    ],
    warnonly = [:missing_docs],
)
