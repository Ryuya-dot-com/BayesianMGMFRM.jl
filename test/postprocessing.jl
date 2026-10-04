# Standalone entry point: synthetic draws only; no MCMC, renderer or saved study results.
module PostprocessingChecks
using Test
@testset "Postprocessing without fitting" begin
    include("posterior_mcse_draws.jl")
    include("posterior_plot.jl")
    include("saved_mgmfrm_contrasts.jl")
    include("response_surface.jl")
    include("mgmfrm_normalized_fit.jl")
end
end
