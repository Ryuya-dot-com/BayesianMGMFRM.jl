using Documenter
using BayesianMGMFRM
for _sym in (
    BayesianMGMFRM.GlassBox._GLASS_BOX_NAMES...,
    BayesianMGMFRM.Legacy._LEGACY_NAMES...,
    BayesianMGMFRM.ValidationSuite._RESEARCH_ROOT_NAMES...,
)
    @eval using BayesianMGMFRM: $(_sym)
end

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
    required = Set(contract.layer1_practitioner)
    missing = sort!(collect(setdiff(required, documented_root_bindings()));
        by = String)
    isempty(missing) || error(
        "layer1_practitioner root bindings missing from the API reference: " *
        join(missing, ", "),
    )
    return nothing
end

check_root_api_documentation()

# The compact source archive omits large galleries. Keep their labels and link
# to the full manual when rebuilding documentation from that archive.
const ARCHIVE_GALLERIES = Set(("category-report", "criterion", "explanatory", "explanatory-diagnostics",
    "integrated-report", "moderation", "posterior-reliability", "prior-predictive-sensitivity",
    "prior-sensitivity", "rater-agreement", "repeated", "visual-guide"))
const GALLERY_LINK = r"(?:\[?!)?\[([^\]\n]+)\]\((assets/[^\s)]+)\)(?:\]\(assets/[^\s)]+\))?"
const ONLINE_MANUAL = "https://ryuya-dot-com.github.io/BayesianMGMFRM.jl/dev/"

function with_manual_source(build)
    src = joinpath(@__DIR__, "src")
    ispath(joinpath(@__DIR__, "..", ".git")) && return build(src)
    all(isdir(joinpath(src, "assets", gallery)) for gallery in ARCHIVE_GALLERIES) && return build(src)
    return mktempdir() do tmp
        copied = cp(src, joinpath(tmp, "src"))
        for name in filter(endswith(".md"), readdir(copied))
            path = joinpath(copied, name)
            content = read(path, String)
            content = replace(content, GALLERY_LINK => function (text)
                link = match(GALLERY_LINK, text)
                label, asset = link.captures
                gallery = split(asset, '/')[2]
                if gallery in ARCHIVE_GALLERIES && !isdir(joinpath(src, "assets", gallery))
                    page = splitext(name)[1]
                    return "[$label]($(ONLINE_MANUAL)$page/)"
                end
                return text
            end)
            write(path, content)
        end
        build(copied)
    end
end

with_manual_source() do source
document = makedocs(;
    debug = true,
    source,
    sitename = "BayesianMGMFRM.jl",
    modules = [BayesianMGMFRM, BayesianMGMFRM.Experimental],
    remotes = nothing,
    checkdocs = :exports,
    build = get(ENV, "BAYESIANMGMFRM_DOCS_BUILD", "build"),
    format = Documenter.HTML(;
        edit_link = nothing,
        repolink = "https://github.com/Ryuya-dot-com/BayesianMGMFRM.jl",
        # Shared navigation and multi-method API help count toward size.
        # Current largest reference is 129.3 KiB; retain the 100 KiB warning.
        size_threshold = 144 * 2^10,
        size_threshold_warn = 100 * 2^10,
    ),
    pagesonly = true,
    pages = [
        "Home" => "index.md",
        "Start Here" => [
            "Your First Rating Analysis" => "first-analysis.md",
            "Installation" => "installation.md",
        ],
        "Task Guides" => [
            "Bayesian Workflow" => "bayesian-workflow.md",
            "Task Recipes" => "examples.md",
            "Data Validation" => "data-validation.md",
            "Bayesian Fitting" => "fitting.md",
            "Custom Stan Adapter & Handoffs" => "stan-adapter.md",
            "Compare Groups on a Linked Scale" => "equating-and-populations.md",
            "Read Category Design Matrices" => "design-matrix-mrcml.md",
            "Frequentist 1D JMLE & MMLE" => "frequentist-mfrm.md",
            "Reading Results and Comparing Models" => "interpreting-results.md",
            "Visualization Gallery" => "visualization-gallery.md",
            "Migrating from Stan and brms" => "migration-stan-brms.md",
            "Migrating from FACETS and ConQuest" => "migration-facets-conquest.md",
        ],
        "Model Guides and Theory" => [
            "Facets and Model Choices" => "learning-guide.md",
            "How Rating Models Work" => "rating-model-theory.md",
            "Model Equations" => "model-equations.md",
            "Expected Scores and Information" => "score-information.md",
            "Prior Sensitivity" => "prior-sensitivity.md",
            "Saved Prediction and Recovery" => "common_prediction_comparison.md",
            "Plan a Rating Study" => "design-planning.md",
        ],
        "Model Extensions" => [
            "Model Extensions Overview" => "experimental.md",
            "User-Named Additive Facets" => "additive-facets.md",
            "Explain Ratings and Rater Severity" => "explanatory-ratings.md",
            "Multivariate Generalizability" => "multivariate-generalizability.md",
            "Analyze Bounded Scores" => "bounded-scores.md",
            "Analyze Correct Counts" => "count-scores.md",
        "Random slopes" => "random-slopes.md",
        "Distributional scores" => "distributional-scores.md",
            "Mixed-Outcome Speaking Models" => "mixed-outcomes.md",
            "Repeated Performances" => "repeated-performances.md",
            "Person-by-Testlet Dependence" => "person-testlet.md",
            "Check Explanatory Models" => "explanatory-diagnostics.md",
            "Compare Criterion Effects" => "criterion-effects.md",
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
            "Model Extensions" => "api-experimental.md",
            "Validation and Evidence" => "api-validation-evidence.md",
        ],
    ],
    warnonly = [:missing_docs],
)
# Documenter's binding/signature check is stricter than a warning count: a new
# omission cannot be offset by documenting a previously omitted binding.
expected_missing = Set(filter(line -> !isempty(line) && !startswith(line, "#"),
    strip.(readlines(joinpath(@__DIR__, "missing-docstrings.txt")))))
actual_missing = Set(string(binding, signature === Union{} ? "" : " :: $signature")
    for (binding, signatures) in Documenter.missingbindings(document)
    for signature in signatures)
actual_missing == expected_missing || error(
    "Docstring coverage changed. New omissions: $(sort!(collect(setdiff(actual_missing, expected_missing)))); " *
    "resolved omissions (remove from baseline): $(sort!(collect(setdiff(expected_missing, actual_missing))))")
end
