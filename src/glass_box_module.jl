"""
    BayesianMGMFRM.GlassBox

Layer-2 mathematical inspection and interoperability namespace for methodological
researchers and advanced workflows.

Load via `using BayesianMGMFRM.GlassBox` to bring target-density constructors,
model contracts, basis descriptors, coordinate maps, non-centered reference
bijections, triangular log-Jacobians, log-density components, analytical
gradients, CmdStan data dictionaries, sampler controls, and the `MRCML`,
`StanAdapter`, `PortableHandoff`, and `ModelOperationMatrix` submodules into scope.
"""
module GlassBox

const _ROOT = parentmodule(@__MODULE__)

const _GLASS_BOX_NAMES = (
    :CmdStanError,
    :MFRMLogDensity,
    :ModelOperationMatrix,
    :MRCML,
    :PortableHandoff,
    :StanAdapter,
    :constraint_table,
    :contract,
    :coordinates,
    :facet_basis,
    :from_ncp_reference,
    :getdesign,
    :identification_declarations,
    :initial_params,
    :log_jacobian_to_ncp,
    :logdensity_and_gradient,
    :loglikelihood,
    :logposterior,
    :logprior,
    :model_equation,
    :model_family_contract,
    :parameter_names,
    :pointwise_loglikelihood,
    :pointwise_loglikelihood_matrix,
    :reparameterize_draws,
    :reparameterize_point,
    :sampler_controls,
    :stan_data,
    :to_ncp_reference,
)

for _sym in _GLASS_BOX_NAMES
    @eval const $(_sym) = getfield(_ROOT, $(QuoteNode(_sym)))
    @eval export $(_sym)
end

end
