using BayesianMGMFRM, CairoMakie

# The qualified package API is also available directly, without including this file.
pathway_map(fit_result; kwargs...) = BayesianMGMFRM.plot_pathway(fit_result; kwargs...)

if abspath(PROGRAM_FILE) == @__FILE__
    length(ARGS) == 2 || error("Usage: julia pathway_map.jl FIT_CACHE OUTPUT.svg")
    open(ARGS[2] * "-note.txt", "w") do note
        save(ARGS[2], pathway_map(load_fit_cache(ARGS[1]); annotation_io = note))
    end
end
