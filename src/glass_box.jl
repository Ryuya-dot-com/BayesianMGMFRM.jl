# Glass-Box Researcher Transparency Surface (Layer 2)
# Exposes mathematical contracts, exact coordinate maps, basis descriptors,
# exact NCP reference bijections, triangular log-Jacobians, log-density
# components, analytical gradients, Stan data dictionaries, and sampler controls
# for methodological verification and cross-engine reproduction.

const _TIC = Experimental.ThreeIndicator.Concurrent

"""
    getdesign(input::Experimental.ThreeIndicator.ConcurrentInput; prior, interaction=:none)

Build the concurrent 9/9/2 mathematical target. Declare `prior=:reference`,
`:steps`, `:combined`, or an explicit `Experimental.ThreeIndicator.ConcurrentPrior`, and listener×word `interaction=:none`, `:diagonal` or
`:full`. Covariance convolution preserves the original hierarchical priors.
Use `initial_params`, `coordinates`, `logprior`, `loglikelihood`, `logposterior`,
`pointwise_loglikelihood` and `logdensity_and_gradient` for inspection.
Fixed-point `event_probabilities` and `contrast` preserve the declared reporting
populations and context; `save_report` / `load_report` retain computed results.
Use `prepare_fit` or `fit` for the concurrent fitted lifecycle, and `qualify`
plus focal MCSE for its numerical disposition.

For mathematical inspection of residual A–C dependence, declare
`association=:plackett, association_log_sd=1.0` (explicit working prior SD on
log(psi)). This appends one global parameter, preserving the original priors and
conditional marginals. The same fitted, inspection and model save/load verbs apply.
`predictive_check(target; ...)` uses independent joint-prior draws;
`predictive_check(fit; ...)` uses retained posterior states and preserves the
A–C joint response law. Marginal event/contrast reports retain the model identity.
Association is unchanged by the optional `pair_132` sampler chart.
"""
function getdesign(input::_TIC.Input;association::Symbol=:independent,association_log_sd=nothing,kwargs...)
    _TIC.require(association in (:independent,:plackett),"association must be :independent or :plackett")
    if association===:independent
        _TIC.require(association_log_sd===nothing,"association_log_sd applies only to :plackett")
        return _TIC.Target(input;kwargs...)
    end
    _TIC.AssociationTarget(_TIC.Target(input;kwargs...);log_sd=association_log_sd)
end
initial_params(t::_TIC.Target) = _TIC.initial(t)
contract(t::_TIC.Target) = _TIC.contract(t)
coordinates(t::_TIC.Target,q::AbstractVector{<:Real}) = _TIC.coordinates(t,q)
logposterior(t::_TIC.Target,q::AbstractVector{<:Real}) = LogDensityProblems.logdensity(t,q)
logprior(t::_TIC.Target,q::AbstractVector{<:Real}) = _TIC.ordinary_prior(t,q)+_TIC.hyper_prior(t,q[t.hyper_indices])
loglikelihood(t::_TIC.Target,q::AbstractVector{<:Real}) = sum(_TIC.pointwise(t,q))
pointwise_loglikelihood(t::_TIC.Target,q::AbstractVector{<:Real}) = _TIC.pointwise(t,q)
design_summary(t::_TIC.Target) = (;events=t.data.N,listeners=t.data.R,words=t.data.W,
    recordings=t.data.J,cohorts=3,predictors=24,fixed_design_rank=27,free_parameters=t.size,
    categories=(9,9,2),interaction=t.interaction,source_rows=copy(t.data.source_rows),scientific_acceptance=false)
parameter_names(t::_TIC.Target) = reduce(vcat,(["$(k)[$i]" for i in 1:length(v)] for (k,v) in sort(collect(t.blocks);by=x->first(last(x)))))
_save_report(path::AbstractString,t::_TIC.Target) = _TIC.save_model(path,t)

"""
    event_probabilities(target::Experimental.ThreeIndicator.ConcurrentTarget, q;
        panel=:observed, rows=nothing)

Evaluate all 9/9/2 category probabilities at one finite parameter point.
`:observed` uses existing target rows (distinct integer `rows`, default all).
`:eng_reference` uses equal weights over preliminary listeners and words at
block 1, position 13, previous ENG-natural and zero log-lags. It retains
cross-study extrapolation warnings. Unknown panels, new levels and reference
row overrides are unsupported. These are computed fixed-point reports, with
no posterior intervals or MCSE. Save/reopen with `save_report` / `load_report`.
"""
event_probabilities(t::_TIC.Target,q::AbstractVector{<:Real};kwargs...) =
    Experimental.ThreeIndicator.ConcurrentReports.probabilities(t,q;kwargs...)

"""
    contrast(target::Experimental.ThreeIndicator.ConcurrentTarget, q)

Evaluate the source's eight signed preliminary-row probability contrasts at
the same parameter point on both sides. Additional-study rows have zero weight.
Retains all category differences, binary correctness and expected ordinal-score
contrasts, with original denominators, model/point identities and warnings.
These observed-assignment averages are not standardized or causal effects.
The input must retain the balanced preliminary 100-trial/five-condition protocol.
No posterior interval, MCSE or empirical qualification is supplied.
"""
contrast(t::_TIC.Target,q::AbstractVector{<:Real}) =
    Experimental.ThreeIndicator.ConcurrentReports.contrasts(t,q)


"""
    contract(x)

Return the machine-readable mathematical, identification, prior, and stability
contract for a model specification, compiled design, density target, or fitted result.
"""
contract(m::_SA_MOD.StarModel) = _SA_MOD.contract()
contract(res::_SA_MOD.StarResult) = _SA_MOD.contract()
contract(t::_C3D_MOD.Target) = _C3D_MOD.contract(t)
contract(t::_JR_MOD.S.Target) = _JR_MOD.contract()
contract(t::_OA_MOD.Target) = _OA_MOD.contract()
contract(t::_RGE_MOD.Target) = _RGE_MOD.contract()
contract(t::_RII_MOD.Target) = _RII_MOD.contract()
contract(t::_CC_MOD.Target) = _CC_MOD.contract()
contract(t::_RD_MOD.M.Target) = _RD_MOD.contract()

function contract(spec::FacetSpec)
    eq = model_equation(spec)
    fam = model_family_contract(spec)
    id = identification_declarations(spec)
    return (;
        schema = "bayesianmgmfrm.model_contract_view.v1",
        family = spec.family,
        dimensions = spec.dimensions,
        thresholds = spec.thresholds,
        discrimination = spec.discrimination,
        family_contract = fam,
        equation = eq,
        identification = id,
    )
end

contract(design::FacetDesign) = contract(design.spec)
contract(target::MFRMLogDensity) = merge(contract(target.design), (; prior = target.prior))
contract(fit::_SupportedCommonFit) = fit_metadata(fit; view = :public)

"""
    parameter_names(x; scale = :raw)

Return the ordered vector of coordinate names for a model specification,
compiled design, log-density target, or fitted result.

Use `scale = :raw` for unconstrained sampler coordinates and `scale = :model`
for reconstructed model-space parameters when distinct.
"""
function parameter_names(m::_SA_MOD.StarModel; scale::Symbol = :raw, space::Union{Nothing, Symbol} = nothing)
    sp = space !== nothing ? space : (scale === :model ? :substantive : scale)
    return _SA_MOD.parameter_names(m; space = sp)
end
parameter_names(res::_SA_MOD.StarResult; scale::Symbol = :raw, space::Union{Nothing, Symbol} = nothing) =
    parameter_names(res.model; scale, space)

function parameter_names(design::FacetDesign; scale::Symbol = :raw)
    scale in (:raw, :model) || throw(ArgumentError("scale must be :raw or :model"))
    scale === :raw && return copy(design.parameter_names)
    layout = fit_ready_parameter_layout(design; view = :public)
    return copy(layout.constrained_parameter_names)
end

parameter_names(spec::FacetSpec; scale::Symbol = :raw) =
    parameter_names(getdesign(spec; preview = spec.family !== :mfrm || spec.dimensions > 1); scale)
parameter_names(target::MFRMLogDensity; scale::Symbol = :raw) =
    parameter_names(target.design; scale)

function parameter_names(fit::_SupportedCommonFit; scale::Symbol = :raw)
    scale in (:raw, :model) || throw(ArgumentError("scale must be :raw or :model"))
    if fit isa MFRMFit
        return parameter_names(fit.design; scale)
    elseif fit isa Union{GMFRMFit, MGMFRMFit}
        return scale === :raw ?
            copy(fit.diagnostic_surface.raw_parameter_names) :
            copy(fit.diagnostic_surface.direct_parameter_names)
    else
        if scale === :raw
            return fit isa _RecordedMGMFRMFit ?
                copy(_recorded_mgmfrm_samples(fit).raw_parameter_names) :
                copy(_fixed_q_report_samples((; fit.record)).parameter_names)
        end
        ctx = _recovery_context(fit)
        return [c.parameter for c in ctx.coordinates]
    end
end

function parameter_names(t::_C3D_MOD.Target; scale::Symbol = :raw)
    scale in (:raw, :model) || throw(ArgumentError("scale must be :raw or :model"))
    raw_names = vcat(t.independent.base.blueprint.parameter_names, ["q21", "q31", "q32"])
    scale === :raw && return raw_names
    q0 = _C3D_MOD.initial(t)
    m = _C3D_MOD.model_draws(t, reshape(q0, 1, :))
    return m.names
end

function parameter_names(t::_JR_MOD.S.Target; scale::Symbol = :raw)
    scale in (:raw, :model) || throw(ArgumentError("scale must be :raw or :model"))
    scale === :raw && return ["$name[$j]" for (name, block) in pairs(t.blocks) for j in eachindex(block)]
    return _JR_MOD.W.model_draws(t, permutedims(_JR_MOD.S.initial(t))).names
end

function parameter_names(t::_OA_MOD.Target; scale::Symbol = :raw)
    scale in (:raw, :model) || throw(ArgumentError("scale must be :raw or :model"))
    scale === :raw && return ["raw[$j]" for j in 1:LogDensityProblems.dimension(t)]
    q0 = _OA_MOD.initial(t)
    return _OA_MOD.model_draws(t, permutedims(q0), zeros(1, 2)).names
end

"""
    facet_basis(x, facet = :entity)

Return the explicit identification basis, effective observation precision counts,
and centered/non-centered partition metadata for a facet (`:entity`/`:person`,
`:rater`, or `:item`).
"""
function facet_basis(m::_SA_MOD.StarModel, facet::Symbol = :entity)
    target = facet === :person ? :entity : facet
    return _SA_MOD.facet_basis(m, target)
end

facet_basis(res::_SA_MOD.StarResult, facet::Symbol = :entity) =
    facet_basis(res.model, facet)

function facet_basis(design::FacetDesign, facet::Symbol = :person)
    target = facet === :entity ? :person : facet
    target in (:person, :rater, :item) ||
        throw(ArgumentError("facet must be :person (:entity), :rater, or :item"))
    data = design.spec.data
    levels = target === :person ? data.person_levels :
        (target === :rater ? data.rater_levels : data.item_levels)
    idx_vec = getproperty(data, target)
    counts = [count(==(k), idx_vec) for k in eachindex(levels)]
    fixed_rows = [r for r in _stable_fixed_coordinate_rows(design) if r.block === target]
    return (;
        facet = target,
        n_levels = length(levels),
        levels = copy(levels),
        observation_counts = counts,
        fixed_levels = fixed_rows,
        parameter_indices = get(design.blocks, target, Int[]),
    )
end

facet_basis(spec::FacetSpec, facet::Symbol = :person) =
    facet_basis(getdesign(spec), facet)
facet_basis(fit::MFRMFit, facet::Symbol = :person) =
    facet_basis(fit.design, facet)

"""
    coordinates(model_or_design, q)

Map an unconstrained sampler vector `q` to structured model-space facet arrays,
thresholds, scales, and correlation matrices.
"""
coordinates(m::_SA_MOD.StarModel, q::AbstractVector{<:Real}) = _SA_MOD.coordinates(m, q)
coordinates(t::_C3D_MOD.Target, q::AbstractVector{<:Real}) = _C3D_MOD.coordinates(t, q)
coordinates(t::_JR_MOD.S.Target, q::AbstractVector{<:Real}) = _JR_MOD.S.coordinates(t, q)
coordinates(t::_OA_MOD.Target, q::AbstractVector{<:Real}) = _OA_MOD.representative(t, q)
coordinates(t::_RGE_MOD.Target, q::AbstractVector{<:Real}) = _RGE_MOD.coordinates(t, q)
coordinates(t::_RII_MOD.Target, q::AbstractVector{<:Real}) = _RII_MOD.coordinates(t, q)
coordinates(t::_CC_MOD.Target, q::AbstractVector{<:Real}) = _CC_MOD.coordinates(t, q)

function coordinates(design::FacetDesign, q::AbstractVector{<:Real})
    _check_fit_supported_mfrm(design, "coordinates")
    _check_parameter_vector(design, q)
    data = design.spec.data
    nsteps = length(data.category_levels) - 1
    items = design.spec.thresholds === :rating_scale ? (1:1) : eachindex(data.item_levels)
    person_block = design.blocks[:person]
    person = [Float64(q[person_block[p]]) for p in eachindex(data.person_levels)]
    rater = [Float64(_stable_facet_value(design, q, :rater, r)) for r in eachindex(data.rater_levels)]
    item = [Float64(_stable_facet_value(design, q, :item, i)) for i in eachindex(data.item_levels)]
    steps = [Float64(_threshold_step(design, q, i, k)) for i in items, k in 1:nsteps]
    return (; person, rater, item, steps)
end

coordinates(target::MFRMLogDensity, q::AbstractVector{<:Real}) =
    coordinates(target.design, q)

"""
    to_ncp_reference(model, q)

Map a parameter vector `q` from the model's active sampling chart (`:cp`, `:ncp`,
or hybrid `:cp_ncp`) into canonical standardized reference coordinates.
"""
to_ncp_reference(m::_SA_MOD.StarModel, q::AbstractVector{<:Real}) =
    _SA_MOD.to_ncp_reference(m, q)
to_ncp_reference(target::MFRMLogDensity, q::AbstractVector{<:Real}) =
    (_check_parameter_vector(target.design, q); Float64.(q))

"""
    from_ncp_reference(model, q_ncp)

Invert `to_ncp_reference`, mapping canonical standardized reference coordinates
into the model's active sampling chart.
"""
from_ncp_reference(m::_SA_MOD.StarModel, q_ncp::AbstractVector{<:Real}) =
    _SA_MOD.from_ncp_reference(m, q_ncp)
from_ncp_reference(target::MFRMLogDensity, q_ncp::AbstractVector{<:Real}) =
    (_check_parameter_vector(target.design, q_ncp); Float64.(q_ncp))

"""
    reparameterize_point(model_dst, model_src, q_src)
    reparameterize_point(q_src, model_src, model_dst)

Exact diffeomorphism transporting a parameter vector `q_src` between two
parameterizations or basis orderings of the same substantive rating model.
"""
reparameterize_point(m_dst::_SA_MOD.StarModel, m_src::_SA_MOD.StarModel, q_src::AbstractVector{<:Real}) =
    _SA_MOD.reparameterize_point(m_dst, m_src, q_src)
reparameterize_point(q_src::AbstractVector{<:Real}, m_src::_SA_MOD.StarModel, m_dst::_SA_MOD.StarModel) =
    _SA_MOD.reparameterize_point(m_dst, m_src, q_src)

"""
    reparameterize_draws(result, target_model)
    reparameterize_draws(draws, source_model, target_model)

Transport a `StarResult` or posterior draw matrix across parameterization charts
(`:cp`, `:ncp`, `:cp_ncp`) or basis orders while updating retained log-densities
via exact triangular change-of-variables Jacobians.
"""
function reparameterize_draws(draws::AbstractMatrix{<:Real}, m_src::_SA_MOD.StarModel, m_dst::_SA_MOD.StarModel)
    S = size(draws, 1)
    out = Matrix{Float64}(undef, S, m_dst.dim)
    for s in 1:S
        out[s, :] .= _SA_MOD.reparameterize_point(m_dst, m_src, view(draws, s, :))
    end
    return out
end
reparameterize_draws(res::_SA_MOD.StarResult, m_dst::_SA_MOD.StarModel) =
    _SA_MOD.reparameterize_draws(res, m_dst)

"""
    log_jacobian_to_ncp(model, q)

Compute the exact log absolute determinant `log |det(d q_ncp / d q)|` of the
mapping from the active sampling chart to standardized reference coordinates,
satisfying `logposterior(m, q) == logposterior(m_ncp, to_ncp_reference(m, q)) + log_jacobian_to_ncp(m, q)`.
"""
log_jacobian_to_ncp(m::_SA_MOD.StarModel, q::AbstractVector{<:Real}) =
    _SA_MOD.log_jacobian_to_ncp(m, q)
log_jacobian_to_ncp(target::MFRMLogDensity, q::AbstractVector{<:Real}) =
    (_check_parameter_vector(target.design, q); 0.0)

# Exact target density extensions across models
logprior(target::MFRMLogDensity, q::AbstractVector{<:Real}) =
    logprior(target.design, q, target.prior)
loglikelihood(target::MFRMLogDensity, q::AbstractVector{<:Real}) =
    loglikelihood(target.design, q)
pointwise_loglikelihood(target::MFRMLogDensity, q::AbstractVector{<:Real}) =
    pointwise_loglikelihood(target.design, q)
logposterior(target::MFRMLogDensity, q::AbstractVector{<:Real}) =
    logposterior(target.design, q, target.prior)

logprior(m::_SA_MOD.StarModel, q::AbstractVector{<:Real}) = _SA_MOD.logprior(m, q)
loglikelihood(m::_SA_MOD.StarModel, q::AbstractVector{<:Real}) = _SA_MOD.loglikelihood(m, q)
pointwise_loglikelihood(m::_SA_MOD.StarModel, q::AbstractVector{<:Real}) =
    _SA_MOD.pointwise_loglikelihood(m, q)
logposterior(m::_SA_MOD.StarModel, q::AbstractVector{<:Real}) = _SA_MOD.logposterior(m, q)

logprior(t::_C3D_MOD.Target, q::AbstractVector{<:Real}) = _C3D_MOD.logprior(t, q)
function loglikelihood(t::_C3D_MOD.Target, q::AbstractVector{<:Real})
    raw, _ = _C3D_MOD.coordinates(t, q)
    return _source_fixture_loglikelihood(t.independent.base, raw)
end
function pointwise_loglikelihood(t::_C3D_MOD.Target, q::AbstractVector{<:Real})
    lp = _C3D_MOD.category_logprobs(t, q)
    cats = t.independent.base.design.spec.data.category
    return [lp[n, cats[n]] for n in eachindex(cats)]
end
logposterior(t::_C3D_MOD.Target, q::AbstractVector{<:Real}) =
    LogDensityProblems.logdensity(t, q)

logposterior(t::_JR_MOD.S.Target, q::AbstractVector{<:Real}) =
    LogDensityProblems.logdensity(t, q)
logposterior(t::_OA_MOD.Target, q::AbstractVector{<:Real}) =
    LogDensityProblems.logdensity(t, q)
logprior(t::_CC_MOD.Target, q::AbstractVector{<:Real}) = _CC_MOD.logprior(t, q)
loglikelihood(t::_CC_MOD.Target, q::AbstractVector{<:Real}) =
    _CC_MOD.components(t, q).loglikelihood
logposterior(t::_CC_MOD.Target, q::AbstractVector{<:Real}) =
    LogDensityProblems.logdensity(t, q)
logposterior(t::_RGE_MOD.Target, q::AbstractVector{<:Real}) =
    LogDensityProblems.logdensity(t, q)
logposterior(t::_RII_MOD.Target, q::AbstractVector{<:Real}) =
    LogDensityProblems.logdensity(t, q)

"""
    logdensity_and_gradient(target, q)

Evaluate `(logp, grad)` simultaneously in unconstrained sampler coordinates `q`.
Uses implemented analytical gradients for `StarAssociation`, `JointRatings`,
`OrdinalAssociation`, `RaterGroupEffects` and `RaterItemInteractions`.
Scalar `MFRMLogDensity` and the correlated 3D route use forward-mode automatic
differentiation here. Other targets dispatch through their LogDensityProblems
capability, falling back to ForwardDiff for order-0 targets. This inspection
method does not by itself select the backend used by a separate fitting call.
"""
logdensity_and_gradient(m::_SA_MOD.StarModel, q::AbstractVector{<:Real}) =
    _SA_MOD.logdensity_and_gradient(m, q)

function logdensity_and_gradient(target::MFRMLogDensity, q::AbstractVector{<:Real})
    _check_parameter_vector(target.design, q)
    qf = Float64.(q)
    val = logposterior(target, qf)
    grad = ForwardDiff.gradient(z -> _logposterior_unchecked(target.design, z, target.prior), qf)
    return (val, grad)
end

function logdensity_and_gradient(t::_C3D_MOD.Target, q::AbstractVector{<:Real})
    qf = Float64.(q)
    st = _C3D_MOD.SamplingTarget(t)
    val = LogDensityProblems.logdensity(st, qf)
    grad = ForwardDiff.gradient(z -> LogDensityProblems.logdensity(st, z), qf)
    return (val, grad)
end

function logdensity_and_gradient(target, q::AbstractVector{<:Real})
    cap = LogDensityProblems.capabilities(typeof(target))
    if cap === LogDensityProblems.LogDensityOrder{0}()
        qf = Float64.(q)
        val = LogDensityProblems.logdensity(target, qf)
        grad = ForwardDiff.gradient(z -> LogDensityProblems.logdensity(target, z), qf)
        return (val, grad)
    end
    return LogDensityProblems.logdensity_and_gradient(target, q)
end

"""
    stan_data(model_or_spec; prior = MFRMPrior())

Export the exact data and hyperparameter dictionary consumed by a corresponding
CmdStan model for independent cross-engine posterior verification.
"""
stan_data(m::_SA_MOD.StarModel) = _SA_MOD.stan_data(m)
stan_data(res::_SA_MOD.StarResult) = _SA_MOD.stan_data(res.model)
stan_data(t::_C3D_MOD.Target) = _C3D_MOD.stan_data(t)
stan_data(design::FacetDesign; prior::MFRMPrior = MFRMPrior()) =
    _cmdstan_mfrm_data(design, prior)
stan_data(spec::FacetSpec; prior::MFRMPrior = MFRMPrior()) =
    _cmdstan_mfrm_data(getdesign(spec), prior)
stan_data(target::MFRMLogDensity) = _cmdstan_mfrm_data(target.design, target.prior)

"""
    sampler_controls(x)

Return the explicit HMC/NUTS adaptation, initialization, metric, seed, and
step-size settings bound to a sampler configuration or saved fit result.
"""
sampler_controls(cfg::_SA_MOD.SamplerConfig) = _SA_MOD.sampler_controls(cfg)
sampler_controls(res::_SA_MOD.StarResult) = _SA_MOD.sampler_controls(res)
sampler_controls(fit::_SupportedCommonFit) = fit_metadata(fit; view = :public).sampler_controls

function sampler_controls(r::NamedTuple)
    tag = _sample_schema_symbol(r)
    tag !== nothing && return r.run.controls
    throw(ArgumentError("unsupported NamedTuple record for sampler_controls"))
end

"""Inspect criterion-collapse held-out conditional densities and proposal ratios;
requires `unit=:performance_rater`. Columns do not factorize the fitted likelihood.
See `Experimental.CriterionCollapse.pointwise_loglikelihood` for conditioning.
"""
function pointwise_loglikelihood(r::NamedTuple;kwargs...)
    _sample_schema_symbol(r)===:criterion_collapse || throw(ArgumentError("this result has no held-out conditional-density adapter"))
    _CC_MOD.pointwise_loglikelihood(r;kwargs...)
end


const _TICW=Experimental.ThreeIndicator.ConcurrentWorkflow
"""
    prepare_fit(target::Experimental.ThreeIndicator.ConcurrentTarget;
                ndraws, warmup, seed, chains=4, kwargs...)
    fit(target::Experimental.ThreeIndicator.ConcurrentTarget;
        directory, ndraws, warmup, seed, chains=4, kwargs...)

Prepare without sampling, or run analytic-gradient NUTS in a new directory.
Optional controls: target_accept=.9, max_depth=10, step_size=.03, init_jitter=.1,
initial=nothing, chain_execution=:serial, max_parallel_chains=chains, parameterization=:native;
`fit` also accepts progress=false or a fresh `SamplingProgress`.
With `chain_execution=:threads`, at most the requested cap, chain count and available
Julia default-pool threads run together. Start Julia with `--threads=2` for two workers.
`fit_report(plan).execution` records requested mode and effective workers. Each chain
keeps its prepared seed in both modes; changing scheduling does not repartition RNGs.
Parallel workers have separate targets, sampler state and adaptation records; they
increase live workspace and do not promise speedup or convergence. Diagonal metric and standard
AdvancedHMC adaptation are retained. Inspect `fit_report(plan)` for numeric-array
storage estimates, seeds, effective adaptation windows and warnings. Short warmup
can leave an identity metric despite a diagonal request. `sampler_controls(result)`
also retains observed metric-change iterations and the final inverse mass. Initial jitter does not guarantee mode exploration.

`parameterization=:pair_132` is an experimental, prior-preserving sampler chart
for `interaction=:full`. Supply `initial` in native model coordinates. Stored draws,
raw summaries (`pair_q_132`), jitter and metric remain in sampler coordinates;
model summaries and probabilities convert each joint draw back to native coordinates.
Plans, reports and `sampler_controls` retain this distinction and its warning.
Improved mixing or precision is unproven. The default `:native` is unchanged.

Each returned/completed chain and failure is saved. On failure, queued chains stop,
active samplers observe cancellation at transition boundaries, and all workers join
before the error returns. Completed files remain inspectable. There is no automatic retry,
lengthening or MCMC resumption. `fit(plan; directory, progress=false)` executes a
prepared plan. `load_fit(directory; require_complete=false)` inspects completed
chains after interruption; incomplete results cannot produce posterior summaries.
Native restoration requires the original source and environment. Read only trusted
native files; after-read checks do not make Julia Serialization safe for untrusted data.
"""
prepare_fit(t::_TIC.Target;kwargs...)=_TICW.prepare(t;kwargs...)
fit(t::_TIC.Target;kwargs...)=_TICW.fit(t;kwargs...)
fit(p::_TICW.Plan;kwargs...)=_TICW.execute(p;kwargs...)
fit_report(p::_TICW.Plan)=_TICW.plan_report(p)
getdesign(f::_TICW.Fit)=_TICW.checked(f;complete=false)
design_summary(f::_TICW.Fit)=design_summary(getdesign(f))
contract(f::_TICW.Fit)=contract(getdesign(f))
parameter_names(f::_TICW.Fit;scale=:model)=scale===:raw ? _TICW.raw_names(getdesign(f);parameterization=f.plan.record.coordinates.name) :
    scale===:model ? _TICW.model_values(getdesign(f),f.plan.record.native_initial).names : throw(ArgumentError("choose :raw or :model"))
sampler_controls(f::_TICW.Fit)=(_TICW.checked(f;complete=false);deepcopy(merge(f.plan.record.controls,(;coordinates=f.plan.record.coordinates,execution=f.plan.record.execution,adaptation_plan=f.plan.record.adaptation_plan,
    adaptation=[(;chain=r.chain,r.adaptation...) for r in f.chains]))))
"""Inspect a concurrent fit's sampler-coordinate vector through the shared mathematical verbs.
`coordinates` returns native effective-model effects; density/gradient use the stored
sampler chart, including its hyperparameter-dependent pullback. See `sampler_controls`.
"""
coordinates(f::_TICW.Fit,q::AbstractVector{<:Real}) =
    (t=getdesign(f); coordinates(t,_TICW.native_point(f.plan,t,q)))
logposterior(f::_TICW.Fit,q::AbstractVector{<:Real}) =
    LogDensityProblems.logdensity(_TICW.sampling_target(f.plan,getdesign(f)),q)
logdensity_and_gradient(f::_TICW.Fit,q::AbstractVector{<:Real}) =
    LogDensityProblems.logdensity_and_gradient(_TICW.sampling_target(f.plan,getdesign(f)),q)
diagnostics(f::_TICW.Fit)=_TICW.diagnostics(f)
qualify(f::_TICW.Fit)=_TICW.qualify(f)
posterior_summary(f::_TICW.Fit;kwargs...)=_TICW.summary(f;kwargs...)
posterior_mcse(f::_TICW.Fit;kwargs...)=_TICW.mcse(f;kwargs...)
"""
    contrast(fit::Experimental.ThreeIndicator.ConcurrentWorkflow.Fit; interval=.95)
    event_probabilities(fit::Experimental.ThreeIndicator.ConcurrentWorkflow.Fit;
                        panel=:observed, rows=nothing, interval=.95)

Evaluate the original eight contrasts, explicit existing observed rows, or the
ENG reference panel in every joint posterior draw. Observed posterior probabilities
require explicit `rows`; `panel=:eng_reference` accepts no row overrides. Average
probabilities before forming each within-draw difference; never subtract interval
endpoints. Reports retain mean, equal-tailed intervals, mean/quantile MCSE,
whole-fit/focal diagnostics, original populations and extrapolation warnings.
Precision limits are 0.005 for probabilities and 0.02 for descriptive expected scores.
Numerical qualification is separate from scientific acceptance. Calculating a large
reference report can be costly; inspect `fit_report(plan)` before sampling/reporting.
"""
contrast(f::_TICW.Fit;kwargs...)=_TICW.posterior(f;operation=:contrasts,kwargs...)
posterior_contrast(f::_TICW.Fit;kwargs...)=contrast(f;kwargs...)
event_probabilities(f::_TICW.Fit;panel=:observed,kwargs...)=_TICW.posterior(f;operation=panel,kwargs...)
fit_report(f::_TICW.Fit;kwargs...)=contrast(f;kwargs...)
save_fit(path::AbstractString,f::_TICW.Fit)=_TICW.save(path,f)
_save_report(path::AbstractString,f::_TICW.Fit;kwargs...)=_TICW.save_report(path,fit_report(f;kwargs...))

stan_data(target::_TIC.Target) = _TIC.stan_data(target)

include("three_indicator/concurrent_association_api.jl")
