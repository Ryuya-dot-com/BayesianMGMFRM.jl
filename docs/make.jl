using Documenter
using BayesianMGMFRM

const ROOT_API_REFERENCE_PAGES = (
    "api-data-design.md",
    "api-fitting-artifacts.md",
    "api-workflow-diagnostics.md",
    "api-validation-evidence.md",
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
    remotes = Dict(
        ".." => (
            Documenter.Remotes.GitHub(
                "Ryuya-dot-com",
                "BayesianMGMFRM.jl",
            ),
            "main",
        ),
    ),
    checkdocs = :exports,
    build = get(ENV, "BAYESIANMGMFRM_DOCS_BUILD", "build"),
    format = Documenter.HTML(;
        edit_link = "main",
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
