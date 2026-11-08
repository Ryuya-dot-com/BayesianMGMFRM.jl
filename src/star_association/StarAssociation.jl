"""
    StarAssociation

Multidimensional rating-event ordinal association model (`D >= 2` criteria with arbitrary
mixed category supports `K_c >= 2`) using a star-factorized conditional potential around a
declared root criterion, correlated zero-sum entity and rater effects (`LKJCholesky`), and
optional reference-profile marginal prior transport.

# Two-Layer Public Interface

1. **Unified Practitioner Workflow (aligned with `BayesianMGMFRM` root verbs)**
   - **Specification & Design Audit**:
     `contract`, `model`, `model_from_events`, `model_from_indexed`, `with_options`,
     `validate_design`, `design_summary`, `parameter_names`
   - **Prior & Synthetic Simulation**:
     `prior_draw`, `simulate` (alias: `generate`), `prior_predictive_check`
   - **MCMC Estimation & Multi-Worker Checkpointing**:
     `fit`, `prepare_fit`, `run_chain_worker`, `worker_status`, `collect_fit`, `from_saved_blocks`
   - **Qualification, Summaries, Contrasts & Measurement Decisions**:
     `qualify` (alias: `diagnostics`), `posterior_summary` (alias: `report`),
     `facet_summary`, `category_summary`, `contrast`, `event_probabilities`,
     `reliability`, `ranking`, `classification`
   - **Streaming Fit Criteria, Predictive Checks, Comparison & Sensitivity**:
     `waic`, `psis_loo`, `criteria`, `predictive_check` (alias: `ppc`),
     `compare_models` (alias: `compare`), `evaluate`, `prior_sensitivity`
   - **Persistence**:
     `save_fit` / `load_fit` (aliases: `save_result` / `load_result`),
     `save_report` / `load_report`

2. **Glass-Box Researcher Transparency Surface**
   - **Basis & Coordinate Geometry**:
     `facet_basis`, `coordinates`, `to_ncp_reference`, `from_ncp_reference`,
     `reparameterize_point`, `reparameterize_draws`, `log_jacobian_to_ncp`
   - **Exact Target Density, Analytical Gradients & External Engine Export**:
     `logprior`, `loglikelihood`, `pointwise_loglikelihood`, `logposterior`,
     `logdensity_and_gradient`, `evaluate_density_gradient`, `stan_data`, `sampler_controls`
"""
module StarAssociation

using LinearAlgebra
using Random
using Serialization
using SHA
using SpecialFunctions
using Statistics
using ForwardDiff
using JSON3

import AdvancedHMC as H
import BayesianMGMFRM as B
import LogDensityProblems as L
import MCMCDiagnosticTools

const LKJ_SOURCE = normpath(
    joinpath(@__DIR__, "..", "correlated_3d_lkj.jl")
)
include(LKJ_SOURCE)
const C = MGMFRMLKJCholeskyCandidate
const LOG2PI = log(2pi)

export StarModel, StarResult, PriorConfig, ParameterizationConfig, SamplerConfig, FacetBasis
export contract, model, model_from_events, model_from_indexed, with_options
export validate_design, design_summary, parameter_names
export prior_draw, simulate, generate, prior_predictive_check
export fit, prepare_fit, run_chain_worker, worker_status, collect_fit, from_saved_blocks
export qualify, diagnostics, posterior_summary, report
export facet_summary, category_summary, contrast, event_probabilities
export reliability, ranking, classification
export waic, psis_loo, criteria, predictive_check, ppc, compare_models, compare, evaluate, prior_sensitivity
export save_fit, load_fit, save_result, load_result, save_report, load_report
export facet_basis, coordinates, to_ncp_reference, from_ncp_reference
export reparameterize_point, reparameterize_draws, log_jacobian_to_ncp
export logprior, loglikelihood, pointwise_loglikelihood, logposterior, logdensity_and_gradient
export stan_data, sampler_controls

"""
    contract()

Return the machine-readable mathematical, numerical, and operational contract of `StarAssociation`.
"""
function contract()
    return (;
        status = :experimental,
        topology = :star_root_to_branches,
        minimum_criteria = 2,
        mixed_category_supports = true,
        minimum_categories_per_criterion = 2,
        distinct_threshold_groups = true,
        coefficients = :fixed_unit,
        parameterizations = (:cp, :ncp, :cp_ncp),
        basis_orders = (:descending_schur, :legacy_lexicographic),
        default_basis_order = :descending_schur,
        effective_count_definition = :rao_searle_schur_complement_harmonic_contrast_precision,
        default_cp_threshold_rule = :papaspiliopoulos_roberts_skold_dimensionless_fisher_to_prior_ratio,
        default_cp_min_info_ratio = 8.0,
        explicit_prior_required = true,
        entity_sd = :estimated_lognormal,
        rater_sd = :estimated_lognormal,
        facet_correlations = :lkj_cholesky_partial_correlations,
        criterion_means = :explicit,
        within_event_association = :optional_star_bilinear_scaled_scores,
        reference_prior_transport = :optional_exact_unit_jacobian_root_margin_transport,
        prior_simulation_and_recovery = true,
        cohort_decisions = (:reliability, :ranking, :classification),
        predictors = false,
        samplers = (:advancedhmc,),
        default_initialization = :overdispersed,
        initialization_modes = (:overdispersed, :prior, :stan_uniform, :multipath_lbfgs, :shared_warmstart),
        default_adaptation = :stan,
        adaptation_modes = (:stan, :clamped_regularized),
        initial_metrics = (:prior_fisher, :unit),
        checkpoint_resume = true,
        scientific_acceptance = false,
        prediction = :existing_rating_event_conditional_probabilities,
        native_cache = :trusted_same_source_and_environment,
        json = :rfc8259_jsonsafe_report,
    )
end

include("schema.jl")
include("kernel.jl")
include("simulation.jl")
include("sampler.jl")
include("result_and_report.jl")
include("qualification.jl")
include("facets_and_categories.jl")
include("streaming_eval.jl")
include("sensitivity.jl")

end
