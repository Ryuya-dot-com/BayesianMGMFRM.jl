# Include this file, load an existing cache, then call saved_mgmfrm_contrast.
# These helpers summarize joint draws; they never fit, resample or change a cache.
using BayesianMGMFRM, Statistics
using BayesianMGMFRM: MCMCDiagnosticTools

paired_contrast_summary(left::AbstractVector, right::AbstractVector; kwargs...) =
    BayesianMGMFRM.posterior_contrast(left, right; kwargs...)

function saved_mgmfrm_contrast(fit::Union{BayesianMGMFRM.MGMFRMFit,BayesianMGMFRM.Experimental.NormalizedMGMFRMFit};
        kind::Symbol, left::AbstractString, right::AbstractString,
        dimension = nothing, interval = 0.9, rope = nothing)
    kind in (:ability, :severity, :log_consistency_ratio) ||
        throw(ArgumentError("Choose :ability, :severity, or :log_consistency_ratio."))
    left != right || throw(ArgumentError("Choose two distinct fitted levels."))
    spec = fit isa BayesianMGMFRM.MGMFRMFit ? fit.design.spec : fit.record.spec
    labels = string.(kind === :ability ? spec.data.person_levels : spec.data.rater_levels)
    a, b = findfirst(==(left), labels), findfirst(==(right), labels)
    a !== nothing && b !== nothing || throw(ArgumentError("Both labels must occur in the saved fit."))
    if kind === :ability
        d = findfirst(==(dimension), spec.dimension_labels)
        d !== nothing || throw(ArgumentError("Supply a stored dimension label for ability differences."))
        coordinates = spec.dimensions == 1 ? ["person[$label]" for label in (left, right)] :
            ["person[$label,$dimension]" for label in (left, right)]
    else
        dimension === nothing || throw(ArgumentError("Rater parameters have no dimension selector."))
        coordinates = kind === :severity ? ["rater[$label]" for label in (left, right)] :
            ["rater_consistency[rater=$label]" for label in (left, right)]
    end
    result = BayesianMGMFRM.posterior_contrast(fit;
        left=coordinates[1], right=coordinates[2],
        operation=kind === :log_consistency_ratio ? :log_ratio : :difference,
        interval, rope)
    summary = result.summary
    return (; kind, left, right, dimension, summary,
        whole_fit_diagnostics = result.whole_fit_diagnostics,
        interpretation = "Left minus right; consistency uses log(left) minus log(right). Positive means higher ability, greater severity, or larger consistency. Ability-difference magnitudes and nonzero ROPE bounds use the saved model's ability unit. Contrasts remain conditional on its prior and rating design. Whole-fit warnings remain applicable; no practical-equivalence or reliability decision is made.")
end
