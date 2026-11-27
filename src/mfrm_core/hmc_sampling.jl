# hmc_sampling.jl -- HMC/NUTS/RWM sampling kernels, control normalization, and fit entrypoints.

function _fit_initial_params(design::FacetDesign, init)
    nparams = length(design.parameter_names)
    if init === nothing
        return zeros(Float64, nparams)
    end
    length(init) == nparams ||
        throw(ArgumentError("init has length $(length(init)); expected $nparams"))
    out = Float64.(collect(init))
    all(isfinite, out) || throw(ArgumentError("init contains non-finite values"))
    return out
end

function _fit_rng(rng::AbstractRNG, seed)
    if seed === nothing
        return rng, (;
            algorithm = Symbol(nameof(typeof(rng))),
            seed = missing,
            replayable = false,
        )
    end
    seed isa Integer ||
        throw(ArgumentError("seed must be an integer or nothing"))
    seed_value = try
        Int(seed)
    catch err
        _fatal_exception(err) && rethrow()
        throw(ArgumentError("seed must fit in Int"))
    end
    seeded_rng = MersenneTwister(seed_value)
    return seeded_rng, (;
        algorithm = :MersenneTwister,
        seed = seed_value,
        replayable = true,
    )
end

function _check_fit_controls(ndraws::Int, warmup::Int, chains::Int, step_size::Real)
    ndraws >= 1 || throw(ArgumentError("ndraws must be positive"))
    warmup >= 0 || throw(ArgumentError("warmup must be non-negative"))
    chains >= 1 || throw(ArgumentError("chains must be positive"))
    step = Float64(step_size)
    isfinite(step) && step > 0 ||
        throw(ArgumentError("step_size must be finite and positive after Float64 conversion"))
    return step
end

function _check_nuts_controls(target_accept::Real, max_depth::Int,
        max_energy_error::Real, init_jitter::Real)
    accept = Float64(target_accept)
    energy_error = Float64(max_energy_error)
    jitter = Float64(init_jitter)
    0 < accept < 1 ||
        throw(ArgumentError("target_accept must be in (0, 1) after Float64 conversion"))
    max_depth >= 1 || throw(ArgumentError("max_depth must be positive"))
    isfinite(energy_error) && energy_error > 0 ||
        throw(ArgumentError("max_energy_error must be finite and positive after Float64 conversion"))
    # Check the original sign too: a tiny negative input can round to -0.0.
    init_jitter >= 0 && isfinite(jitter) ||
        throw(ArgumentError("init_jitter must be non-negative and finite after Float64 conversion"))
    return accept, energy_error, jitter
end

function _stan_nuts_alias_help_note(alias_name::Symbol, canonical_name::Symbol, value, caller::AbstractString; backend::Union{Nothing,Symbol} = nothing)
    backend_hint = backend === :julia ?
        " Note: `backend = :julia` runs random-walk Metropolis; select `backend = :advancedhmc` or `:cmdstan` for NUTS." : ""
    return "`$(alias_name) = $(value)` accepted as a Stan/brms alias for `$(canonical_name)` in `$(caller)`. " *
        "Use `$(canonical_name)` directly; see `?BayesianMGMFRM.fit` (or `?BayesianMGMFRM.StanAdapter.fit_stan`) " *
        "and the Stan/brms migration guide for `target_accept` / `max_depth` help and model-specific defaults." * backend_hint
end

function _resolve_stan_nuts_aliases(;
        target_accept::Union{Nothing,Real} = nothing,
        adapt_delta::Union{Nothing,Real} = nothing,
        default_target_accept::Real,
        max_depth::Union{Nothing,Int} = nothing,
        max_treedepth::Union{Nothing,Int} = nothing,
        default_max_depth::Int,
        caller::AbstractString = "fit",
        backend::Union{Nothing,Symbol} = nothing,
        emit_info::Bool = true)
    (target_accept isa Bool || adapt_delta isa Bool) &&
        throw(ArgumentError("`target_accept` (alias `adapt_delta`) must be a real number strictly in (0, 1); see `?BayesianMGMFRM.fit`"))
    (max_depth isa Bool || max_treedepth isa Bool) &&
        throw(ArgumentError("`max_depth` (alias `max_treedepth`) must be a positive integer; see `?BayesianMGMFRM.fit`"))
    if target_accept !== nothing && adapt_delta !== nothing
        throw(ArgumentError(
            "cannot specify both `adapt_delta` and `target_accept` in $(caller); " *
            "`adapt_delta` is a Stan/brms alias for canonical `target_accept` (see `?BayesianMGMFRM.fit`)"))
    end
    if max_depth !== nothing && max_treedepth !== nothing
        throw(ArgumentError(
            "cannot specify both `max_treedepth` and `max_depth` in $(caller); " *
            "`max_treedepth` is a Stan/brms alias for canonical `max_depth` (see `?BayesianMGMFRM.fit`)"))
    end
    ta_val = something(target_accept, adapt_delta, default_target_accept)
    md_val = Int(something(max_depth, max_treedepth, default_max_depth))
    if adapt_delta !== nothing
        ta_f = Float64(ta_val)
        0.0 < ta_f < 1.0 || throw(ArgumentError(
            "`adapt_delta` (alias for `target_accept`) must lie strictly in (0, 1) after Float64 conversion; see `?BayesianMGMFRM.fit`"))
        emit_info && @info _stan_nuts_alias_help_note(:adapt_delta, :target_accept, ta_f, caller; backend)
    end
    if max_treedepth !== nothing
        md_val >= 1 || throw(ArgumentError(
            "`max_treedepth` (alias for `max_depth`) must be >= 1; see `?BayesianMGMFRM.fit`"))
        emit_info && @info _stan_nuts_alias_help_note(:max_treedepth, :max_depth, md_val, caller; backend)
    end
    return ta_val, md_val
end

function _normalize_stan_nuts_kwargs(kwargs; caller::AbstractString = "fit", emit_info::Bool = true)
    nt = (; kwargs...)
    has_ad = haskey(nt, :adapt_delta)
    has_mt = haskey(nt, :max_treedepth)
    (has_ad || has_mt) || return nt
    ad_v = has_ad ? nt[:adapt_delta] : nothing
    mt_v = has_mt ? nt[:max_treedepth] : nothing
    ta_v = haskey(nt, :target_accept) ? nt[:target_accept] : nothing
    md_v = haskey(nt, :max_depth) ? nt[:max_depth] : nothing
    mt_v !== nothing && !(mt_v isa Int) && !(mt_v isa Bool) &&
        throw(TypeError(Symbol(caller), "keyword argument max_treedepth", Int, mt_v))
    md_v !== nothing && !(md_v isa Int) && !(md_v isa Bool) &&
        throw(TypeError(Symbol(caller), "keyword argument max_depth", Int, md_v))
    backend = haskey(nt, :backend) && nt[:backend] isa Symbol ? nt[:backend] : nothing
    ta_res, md_res = _resolve_stan_nuts_aliases(;
        target_accept = ta_v,
        adapt_delta = ad_v,
        default_target_accept = 0.80,
        max_depth = md_v isa Bool ? md_v : (md_v === nothing ? nothing : Int(md_v)),
        max_treedepth = mt_v isa Bool ? mt_v : (mt_v === nothing ? nothing : Int(mt_v)),
        default_max_depth = 10,
        caller,
        backend,
        emit_info)
    stripped = Base.structdiff(nt, (; adapt_delta = nothing, max_treedepth = nothing))
    if has_ad && nt[:adapt_delta] !== nothing
        stripped = merge(stripped, (; target_accept = ta_res))
    end
    if has_mt && nt[:max_treedepth] !== nothing
        stripped = merge(stripped, (; max_depth = md_res))
    end
    return stripped
end

function _resolve_bfmi_alias(;
        min_bfmi::Union{Nothing,Real} = nothing,
        ebfmi_min::Union{Nothing,Real} = nothing,
        bfmi_min::Union{Nothing,Real} = nothing,
        default_min_bfmi::Float64 = 0.30,
        caller::AbstractString = "qualify",
        emit_info::Bool = true)
    n_set = count(!isnothing, (min_bfmi, ebfmi_min, bfmi_min))
    n_set <= 1 || throw(ArgumentError(
        "specify at most one of `min_bfmi` (canonical), `ebfmi_min`, or `bfmi_min` in $(caller)"))
    raw = something(min_bfmi, ebfmi_min, bfmi_min, default_min_bfmi)
    raw isa Bool && throw(ArgumentError("min_bfmi must be a finite positive real number"))
    val = Float64(raw)
    isfinite(raw) && isfinite(val) && val > 0.0 ||
        throw(ArgumentError("min_bfmi must be finite and positive"))
    if emit_info && ebfmi_min !== nothing
        @info "`ebfmi_min = $(val)` accepted as an alias for canonical `min_bfmi` in `$(caller)` (see `?BayesianMGMFRM.qualify`)."
    elseif emit_info && bfmi_min !== nothing
        @info "`bfmi_min = $(val)` accepted as an alias for canonical `min_bfmi` in `$(caller)` (see `?BayesianMGMFRM.qualify`)."
    end
    return val
end

"""
    fit(spec_or_design; prior = MFRMPrior(), backend = :julia,
        ndraws = 1000, warmup = 1000, chains = 1, kwargs...)

Estimate a stable one-dimensional MFRM from a specification made by
[`mfrm_spec`](@ref). Return an `MFRMFit` containing retained posterior draws,
the model/data description and sampling information.

Choose `backend = :advancedhmc` for Julia NUTS or `:cmdstan` for CmdStan NUTS.
The compatibility default `:julia` is random-walk Metropolis, not NUTS.
`ndraws` and `warmup` are counts **per chain** (`ndraws` is post-warmup retained
draws, matching `cmdstanr`'s `iter_sampling` rather than `rstan`/`brms` total `iter`).
For NUTS backends, canonical tuning keywords are `target_accept` (default `0.80` on
1D MFRM; `0.85` on `StarAssociation`; `0.90` on hierarchical/explanatory/ZOIB/StanAdapter
routes) and `max_depth` (default `10`). Stan/brms names `adapt_delta` and
`max_treedepth` are accepted as aliases (supplying both names for one control is
an error) and emit an informational hint pointing to `target_accept` / `max_depth`.
The default single chain is insufficient for between-chain convergence checks;
request multiple chains and inspect `diagnostics` and `qualify` (including E-BFMI
`min_bfmi = 0.30`) before interpreting results.

# Examples

After constructing `spec` using the example in [`FacetData`](@ref), this code
runs a deliberately short sampler demonstration:

```julia
fit_result = fit(spec; backend = :advancedhmc,
    chains = 2, warmup = 50, ndraws = 50, seed = 102)
check = diagnostics(fit_result; view = :public)
check.summary.flag
posterior_summary(fit_result)
posterior_mcse(fit_result)
```

These short settings are not adequate-inference recommendations. A completed
fit or a passing diagnostic flag does not establish model validity or interval
coverage. Select priors with [`prior_predictive_check`](@ref) before an analysis;
use [`save_fit_cache`](@ref) and [`load_fit_cache`](@ref) to reuse a fit.

GMFRM, multidimensional MFRM and MGMFRM require the documented
route and its model-specific priors and restrictions; see
[`BayesianMGMFRM.Experimental.fit`](@ref). Type `??fit` for all backend controls.

# Extended help

    fit(spec_or_design; prior = MFRMPrior(), backend = :julia, ndraws = 1000,
        warmup = 1000, chains = 1, step_size = 0.05, init = nothing,
        rng = Random.default_rng(), seed = nothing, target_accept = 0.8,
        max_depth = 10, max_energy_error = 1000.0, metric = :diagonal,
        ad_backend = :ForwardDiff, init_jitter = 0.0, progress = false,
        cmdstan_path = nothing, cmdstan_cache_dir = nothing)
    BayesianMGMFRM.Experimental.fit(spec; backend = :advancedhmc, ...)
    BayesianMGMFRM.Experimental.fit(spec; backend = :cmdstan, ...)

Fit a Bayesian MFRM with rating-scale or partial-credit thresholds using the selected
backend. `backend = :julia` uses a random-walk Metropolis kernel,
`backend = :advancedhmc` uses AdvancedHMC/NUTS directly.
The Turing backend is optional: install it in the analysis environment with
`Pkg.add("Turing")`, then run `import Turing` before fitting. Core operations and
saved result types do not require loading Turing.

`backend = :turing` wraps the same `MFRMLogDensity` target in a Turing/NUTS
model. `backend = :cmdstan` compiles the package-owned stable MFRM Stan model,
runs CmdStan's NUTS command-line interface, and converts its retained draws and
sampler columns to the same `MFRMFit` result. CmdStan is discovered through
`cmdstan_path`, `CMDSTAN`, `CMDSTAN_HOME`, or a versioned `~/.cmdstan`
installation. Supplying `seed` uses a local `MersenneTwister(seed)` and records the
seed in `sampler_controls`; otherwise the supplied `rng` is used without a
replayable seed record.

`step_size` must remain finite and positive after conversion to `Float64`.
For NUTS backends, the converted `target_accept` must lie strictly between zero
and one, `max_energy_error` must be finite and positive, and `init_jitter` must
be non-negative and remain finite. CmdStan requires `max_energy_error = 1000.0`.
Turing adapts for exactly `warmup` transitions per chain, independently of
`ndraws`; zero warmup disables adaptation. Its initial state and all adapting
transitions are excluded from the retained result.

Both guarded generalized configurations accept `:advancedhmc` and `:cmdstan`.
Their CmdStan adapters sample the same raw-coordinate targets, apply the Julia
direct-parameter transforms, and check generated pointwise log likelihoods
against Julia at every retained draw. MGMFRM remains limited to its fixed-Q,
identity-correlation confirmatory contract.

For structured chain/phase counts and a compact overall bar, pass
`progress = SamplingProgress()` to AdvancedHMC. Read [`progress_snapshot`](@ref)
or select a new JSON path in the monitor. Completion counts transitions, not
convergence or saving; Boolean progress retains the original backend display.

The AdvancedHMC backend accepts `ad_backend = :ForwardDiff` by default.
`ad_backend = :ReverseDiff` can be used when the corresponding AD package is
available in the active environment, and `ad_backend = :analytic` uses a
target-provided `LogDensityProblems.logdensity_and_gradient` method when one
exists. The Turing backend currently accepts `ad_backend = :ForwardDiff`;
analytic target gradients are not consumed by Turing's model trace, and the
ReverseDiff path is left to a future adapter after the Turing AD interface can
support this wrapped target reliably.

The `BayesianMGMFRM.Experimental` namespace is intentionally narrow. The
legacy `experimental = true` keyword remains source-compatible. Both routes
are accepted for
the scalar source-aligned GMFRM configuration with `family = :gmfrm`,
`dimensions = 1`, `thresholds = :partial_credit`, and
`discrimination = :rater`, returning [`GMFRMFit`](@ref),
and for the fixed-Q confirmatory MGMFRM candidate with `family = :mgmfrm`,
`dimensions >= 1`, `thresholds = :partial_credit`,
`discrimination = :none`, and a fixed `q_matrix`, returning
[`MGMFRMFit`](@ref). Both generalized surfaces require empty anchors and no
fitted validation-bias/DFF terms. Multidimensional GMFRM, rating-scale
generalized kernels, exploratory MGMFRM loadings, free latent correlations,
non-rater GMFRM discrimination, non-default generic MGMFRM discrimination,
and `MFRMPrior` priors for generalized raw-coordinate fits are rejected before
compilation or cache lookup. Guarded generalized fits accept
`BayesianMGMFRM.Experimental.GeneralizedPrior`; its scales apply only to raw
unconstrained coordinates.
`chain_execution=:threads` enables bounded parallel chains for AdvancedHMC;
`max_parallel_chains` defaults to `chains`. Threaded mode uses recorded independent
chain seeds and preserves draws across worker caps in the same environment.
Its RNG partition differs from the default `:serial` mode, whose stream is unchanged.
Progress aggregates all chains. See the fitting guide for memory and backend limits.
"""
function fit(design::FacetDesign;
        method::Union{Nothing,Symbol} = nothing,
        prior::MFRMPrior = MFRMPrior(),
        backend::Symbol = :julia,
        ndraws::Int = 1000,
        warmup::Int = 1000,
        chains::Int = 1,
        step_size::Real = 0.05,
        init = nothing,
        rng::AbstractRNG = Random.default_rng(),
        seed = nothing,
        target_accept::Union{Nothing,Real} = nothing,
        adapt_delta::Union{Nothing,Real} = nothing,
        max_depth::Union{Nothing,Int} = nothing,
        max_treedepth::Union{Nothing,Int} = nothing,
        max_energy_error::Real = 1000.0,
        metric::Symbol = :diagonal,
        ad_backend::Symbol = :ForwardDiff,
        init_jitter::Real = 0.0,
        progress::Union{Bool,SamplingProgress} = false,
        chain_execution::Symbol = :serial,
        max_parallel_chains::Int = chains,
        cmdstan_path::Union{Nothing,AbstractString} = nothing,
        cmdstan_cache_dir::Union{Nothing,AbstractString} = nothing,
        _on_enter = nothing,
        freq_kwargs...)
    if method !== nothing
        (target_accept === nothing && adapt_delta === nothing && max_depth === nothing && max_treedepth === nothing) ||
            throw(ArgumentError("NUTS controls (`target_accept`/`adapt_delta`, `max_depth`/`max_treedepth`) do not apply to frequentist `method = $(repr(method))`"))
        return FrequentistMFRM.fit(design; method, freq_kwargs...)
    end
    isempty(freq_kwargs) || throw(MethodError(fit, (design,)))
    ta_resolved, md_resolved = _resolve_stan_nuts_aliases(;
        target_accept, adapt_delta, default_target_accept = 0.8,
        max_depth, max_treedepth, default_max_depth = 10,
        caller = "fit", backend)
    target_accept = ta_resolved
    max_depth = md_resolved
    _check_sampling_progress(progress, backend)
    _check_chain_execution(chain_execution, max_parallel_chains, backend; allow_auto = true)
    # Private synchronous observation boundary; entry is not sampler startup.
    _reject_mfrm_fixed_q_fit(design.spec, "fit")
    _on_enter === nothing || _on_enter()
    step_size = _check_fit_controls(ndraws, warmup, chains, step_size)
    if backend !== :cmdstan &&
            (cmdstan_path !== nothing || cmdstan_cache_dir !== nothing)
        throw(ArgumentError(
            "cmdstan_path and cmdstan_cache_dir apply only to backend = :cmdstan",
        ))
    end
    execution_design = _validated_design_snapshot(design, "fit")
    initial = _fit_initial_params(execution_design, init)
    fit_rng, rng_control = _fit_rng(rng, seed)

    if backend === :julia
        return _fit_random_walk(execution_design, prior, ndraws, warmup, chains,
            Float64(step_size), initial, fit_rng, rng_control; record_warmup = true)
    elseif backend === :advancedhmc
        return _fit_advancedhmc(execution_design, prior, ndraws, warmup, chains,
            Float64(step_size), initial, fit_rng, rng_control;
            record_warmup = true,
            target_accept,
            max_depth,
            max_energy_error,
            metric,
            ad_backend,
            init_jitter,
            progress, chain_execution, max_parallel_chains)
    elseif backend === :turing
        return _fit_turing(execution_design, prior, ndraws, warmup, chains,
            Float64(step_size), initial, fit_rng, rng_control;
            record_warmup = true,
            target_accept,
            max_depth,
            max_energy_error,
            metric,
            ad_backend,
            init_jitter,
            progress)
    elseif backend === :cmdstan
        return _fit_cmdstan(execution_design, prior, ndraws, warmup, chains,
            Float64(step_size), initial, fit_rng, rng_control;
            record_warmup = true,
            target_accept,
            max_depth,
            max_energy_error,
            metric,
            ad_backend,
            init_jitter,
            progress,
            cmdstan_path,
            cmdstan_cache_dir)
    else
        throw(ArgumentError(
            "backend must be :julia, :advancedhmc, :turing, or :cmdstan",
        ))
    end
end

function _random_walk_stat_row(;
        chain::Int,
        iteration::Int,
        accepted::Bool,
        nonfinite_proposal::Bool,
        step_size::Float64,
        log_density::Float64)
    return (;
        chain,
        iteration,
        is_adapt = false,
        is_accept = accepted,
        acceptance_rate = accepted ? 1.0 : 0.0,
        log_density,
        hamiltonian_energy = missing,
        hamiltonian_energy_error = missing,
        max_hamiltonian_energy_error = missing,
        n_steps = missing,
        tree_depth = missing,
        numerical_error = nonfinite_proposal,
        nonfinite_proposal,
        step_size,
        nom_step_size = step_size,
    )
end

struct _SamplerError <: Exception
    backend::Symbol
    chain::Int
    phase::Symbol
    cause::CapturedException
end

function Base.showerror(io::IO, err::_SamplerError)
    print(io, err.backend, " chain ", err.chain, " failed during ", err.phase, ": ")
    showerror(io, err.cause)
end

function _with_sampler_context(operation, backend::Symbol, chain::Int, phase::Symbol)
    try
        return operation()
    catch err
        _fatal_exception(err) && rethrow()
        # Preserve CmdStan's existing public stage/reason contract.
        err isa CmdStanError && throw(CmdStanError(err.stage, err.reason,
            "chain $chain ($phase): $(err.detail)"))
        # Validation keeps its existing exception type, including invalid starts.
        err isa ArgumentError && phase in (:initialization, :output_validation) &&
            throw(ArgumentError("$backend chain $chain failed during $phase: $(err.msg)"))
        throw(_SamplerError(backend, chain, phase, CapturedException(err, catch_backtrace())))
    end
end

function _fit_random_walk(design::FacetDesign,
        prior::MFRMPrior,
        ndraws::Int,
        warmup::Int,
        chains::Int,
        step::Float64,
        initial::Vector{Float64},
        rng::AbstractRNG,
        rng_control::NamedTuple;
        record_warmup::Bool = false)
    nparams = length(design.parameter_names)
    total_draws = ndraws * chains
    draws = Matrix{Float64}(undef, total_draws, nparams)
    logps = Vector{Float64}(undef, total_draws)
    chain_ids = Vector{Int}(undef, total_draws)
    iterations = Vector{Int}(undef, total_draws)
    chain_acceptance = Vector{Float64}(undef, chains)
    sampler_stats = NamedTuple[]
    warmup_counts = record_warmup ? zeros(Int, chains) : nothing
    total = warmup + ndraws
    total_accepted = 0

    for chain in 1:chains
        initial_lp = _with_sampler_context(:julia, chain, :initialization) do
            value = _logposterior_unchecked(design, initial, prior)
            isfinite(value) || throw(ArgumentError("initial parameter vector has non-finite log posterior"))
            value
        end
        accepted = _with_sampler_context(:julia, chain, :sampling) do
            current = copy(initial)
            current_lp = initial_lp
            proposal = similar(current)
            chain_accepted = 0
            for iter in 1:total
                @inbounds for j in 1:nparams
                    proposal[j] = current[j] + step * randn(rng)
                end
                proposal_lp = all(isfinite, proposal) ?
                    _logposterior_unchecked(design, proposal, prior) : NaN
                nonfinite_proposal = !isfinite(proposal_lp)
                # Consume the acceptance uniform even for invalid proposals, preserving
                # the seeded stream and the last valid state after rejection.
                log_uniform = log(rand(rng))
                is_accepted = false
                if !nonfinite_proposal && log_uniform < proposal_lp - current_lp
                    current .= proposal
                    current_lp = proposal_lp
                    chain_accepted += 1
                    is_accepted = true
                end
                if iter <= warmup
                    warmup_counts === nothing || (warmup_counts[chain] += nonfinite_proposal)
                else
                    iteration = iter - warmup
                    row = (chain - 1) * ndraws + iteration
                    draws[row, :] .= current
                    logps[row] = current_lp
                    chain_ids[row] = chain
                    iterations[row] = iteration
                    push!(sampler_stats, _random_walk_stat_row(;
                        chain,
                        iteration,
                        accepted = is_accepted,
                        nonfinite_proposal,
                        step_size = step,
                        log_density = current_lp))
                end
            end
            return chain_accepted
        end
        chain_acceptance[chain] = accepted / total
        total_accepted += accepted
    end

    return MFRMFit(design, prior, draws, logps, total_accepted / (total * chains),
        chain_ids, iterations, chain_acceptance, :julia, :random_walk_metropolis,
        warmup, step, sampler_stats, _with_warmup_diagnostics((;
            ndraws,
            warmup,
            chains,
            step_size = step,
            rng = rng_control,
            init_jitter = 0.0,
        ), warmup_counts, :julia))
end

function _advancedhmc_metric(metric::Symbol, nparams::Int)
    metric === :diagonal && return AdvancedHMC.DiagEuclideanMetric(nparams)
    metric === :unit && return AdvancedHMC.UnitEuclideanMetric(nparams)
    metric === :dense && return AdvancedHMC.DenseEuclideanMetric(nparams)
    throw(ArgumentError("metric must be :diagonal, :unit, or :dense"))
end

# Inspect the same stock adaptor used by the generalized runner; do not infer
# metric learning merely from a requested diagonal/dense metric or warmup > 0.
_advancedhmc_adaptor(metric, integrator, target_accept, warmup) = warmup > 0 ?
    AdvancedHMC.StanHMCAdaptor(AdvancedHMC.MassMatrixAdaptor(metric),
        AdvancedHMC.StepSizeAdaptor(Float64(target_accept), integrator)) :
    AdvancedHMC.NoAdaptation()

function _advancedhmc_adaptation_plan(warmup::Int, metric::Symbol)
    warmup >= 0 || throw(ArgumentError("warmup must be nonnegative"))
    m = _advancedhmc_metric(metric, 1)
    a = _advancedhmc_adaptor(m, AdvancedHMC.Leapfrog(.03), .8, warmup)
    if warmup > 0
        AdvancedHMC.Adaptation.initialize!(a, warmup)
    end
    updates = warmup > 0 && metric !== :unit ? copy(a.state.window_splits) : Int[]
    warnings = metric !== :unit && isempty(updates) ?
        ["No mass-matrix learning is scheduled; the initial identity metric is retained. A diagonal/dense request alone does not imply learned scales."] : String[]
    (; backend=:advancedhmc, version=string(Base.pkgversion(AdvancedHMC)), metric,
        warmup, step_size_adaptation=warmup>0, mass_matrix_adaptation=!isempty(updates),
        initial_buffer=warmup>0 ? a.init_buffer : nothing,
        terminal_buffer=warmup>0 ? a.term_buffer : nothing,
        initial_window=warmup>0 ? a.window_size : nothing,
        window_start=warmup>0 ? a.state.window_start : nothing,
        window_end=warmup>0 ? a.state.window_end : nothing,
        scheduled_metric_updates=updates, warnings)
end

function _advancedhmc_initial(initial::Vector{Float64},
        rng::AbstractRNG,
        init_jitter::Float64)
    init_jitter == 0.0 && return copy(initial)
    out = copy(initial)
    for index in eachindex(out)
        out[index] += init_jitter * randn(rng)
    end
    return out
end

function _advancedhmc_stat_row(stat::NamedTuple, chain::Int, iteration::Int)
    getstat(name, default) = hasproperty(stat, name) ? getproperty(stat, name) : default
    return (;
        chain,
        iteration,
        is_adapt = Bool(getstat(:is_adapt, false)),
        is_accept = Bool(getstat(:is_accept, true)),
        acceptance_rate = Float64(getstat(:acceptance_rate, NaN)),
        log_density = Float64(getstat(:log_density, getstat(:logjoint, NaN))),
        hamiltonian_energy = Float64(getstat(:hamiltonian_energy, NaN)),
        hamiltonian_energy_error = Float64(getstat(:hamiltonian_energy_error, NaN)),
        max_hamiltonian_energy_error = Float64(getstat(:max_hamiltonian_energy_error, NaN)),
        n_steps = Int(getstat(:n_steps, 0)),
        tree_depth = Int(getstat(:tree_depth, 0)),
        numerical_error = Bool(getstat(:numerical_error, false)),
        step_size = Float64(getstat(:step_size, NaN)),
        nom_step_size = Float64(getstat(:nom_step_size, NaN)),
    )
end

# Compact warmup telemetry only; never posterior draws or convergence metrics.
function _warmup_stat_row(stat::NamedTuple, chain::Int, iteration::Int)
    all(name -> hasproperty(stat, name),
        (:is_adapt, :numerical_error, :tree_depth, :log_density)) &&
        stat.is_adapt === true && stat.numerical_error isa Bool &&
        stat.tree_depth isa Integer && stat.tree_depth >= 0 &&
        stat.log_density isa Real || throw(ArgumentError("invalid warmup sampler statistic"))
    return (; chain, iteration, divergent = stat.numerical_error,
        tree_depth = Int(stat.tree_depth), nonfinite_logdensity = !isfinite(stat.log_density))
end

function _warmup_diagnostic_rows(stats, controls::NamedTuple, backend::Symbol)
    warmup, chains = controls.warmup, controls.chains
    warmup >= 0 && chains >= 1 || throw(ArgumentError("invalid warmup dimensions"))
    if backend === :julia
        # Random walk counts rejected proposals in place, without transition buffers.
        stats === nothing || (stats isa AbstractVector && length(stats) == chains &&
            all(n -> n isa Int && 0 <= n <= warmup, stats)) ||
            throw(ArgumentError("invalid random-walk warmup proposal counts"))
        available = stats !== nothing || warmup == 0
        return [(; phase = :warmup, backend, chain, expected_iterations = warmup,
            observed_iterations = available ? warmup : missing,
            coverage = warmup == 0 ? :not_run : available ? :recorded : :not_recorded,
            n_divergences = missing, n_max_treedepth = missing,
            n_nonfinite_logdensity = missing,
            n_nonfinite_proposals = stats === nothing ? (warmup == 0 ? 0 : missing) : stats[chain])
            for chain in 1:chains]
    end
    if stats !== nothing
        stats isa AbstractVector && length(stats) == Base.checked_mul(warmup, chains) ||
            throw(ArgumentError("warmup statistic count does not match expected coverage"))
        for (index, row) in enumerate(stats)
            row isa NamedTuple && keys(row) ==
                (:chain, :iteration, :divergent, :tree_depth, :nonfinite_logdensity) &&
                row.chain isa Int && row.chain == div(index - 1, warmup) + 1 &&
                row.iteration isa Int && row.iteration == mod(index - 1, warmup) + 1 &&
                row.divergent isa Bool && row.tree_depth isa Int && row.tree_depth >= 0 &&
                row.nonfinite_logdensity isa Bool ||
                throw(ArgumentError("invalid warmup statistic or chain/iteration layout"))
        end
    end
    return [begin
        available = stats !== nothing || warmup == 0
        rows = stats === nothing ? NamedTuple[] : view(stats, ((chain - 1) * warmup + 1):(chain * warmup))
        (; phase = :warmup, backend, chain, expected_iterations = warmup,
            observed_iterations = available ? warmup : missing,
            coverage = warmup == 0 ? :not_run : available ? :recorded : :not_recorded,
            n_divergences = available ? count(r -> r.divergent, rows) : missing,
            n_max_treedepth = available ? count(r -> r.tree_depth >= controls.max_depth, rows) : missing,
            n_nonfinite_logdensity = available ? count(r -> r.nonfinite_logdensity, rows) : missing)
    end for chain in 1:chains]
end

# Keep the serialized fit layout and retained sampler_stats unchanged. The
# existing sampler metadata carries compact chain summaries, not warmup draws.
function _with_warmup_diagnostics(controls::NamedTuple, stats, backend::Symbol)
    stats === nothing && return controls
    return merge(controls, (; warmup_diagnostics =
        _warmup_diagnostic_rows(stats, controls, backend)))
end

function _fit_warmup_diagnostics(fit::_ModelComparisonFit)
    controls = (; warmup = fit.warmup, chains = length(fit.chain_acceptance_rate))
    fallback = _warmup_diagnostic_rows(nothing, controls, fit.backend)
    # Older Turing requests could adapt even when warmup was zero.
    legacy_turing = fit.backend === :turing && !hasproperty(fit.sampler_controls, :nadapts)
    if legacy_turing
        fallback = [merge(row, (; observed_iterations = missing, coverage = :not_recorded,
            n_divergences = missing, n_max_treedepth = missing,
            n_nonfinite_logdensity = missing)) for row in fallback]
    end
    hasproperty(fit.sampler_controls, :warmup_diagnostics) || return fallback
    rows = fit.sampler_controls.warmup_diagnostics
    rows isa AbstractVector && length(rows) == controls.chains ||
        throw(ArgumentError("warmup diagnostic count does not match fit chains"))
    for (row, expected) in zip(rows, fallback)
        row isa NamedTuple && keys(row) == keys(expected) &&
            row.chain isa Int && row.expected_iterations isa Int &&
            isequal((row.phase, row.backend, row.chain, row.expected_iterations),
                (expected.phase, expected.backend, expected.chain, expected.expected_iterations)) ||
            throw(ArgumentError("warmup diagnostic identity does not match fit"))
        counts = (row.n_divergences, row.n_max_treedepth, row.n_nonfinite_logdensity)
        if fit.backend === :julia
            all(ismissing, counts) || throw(ArgumentError(
                "random-walk warmup does not report NUTS event counts"))
            counts = (row.n_nonfinite_proposals,)
        end
        valid = if row.coverage === :not_recorded && (fit.warmup > 0 || legacy_turing)
            ismissing(row.observed_iterations) && all(ismissing, counts)
        else
            !legacy_turing && row.coverage === (fit.warmup == 0 ? :not_run : :recorded) &&
                row.observed_iterations isa Int && row.observed_iterations == fit.warmup &&
                all(n -> n isa Int && 0 <= n <= fit.warmup, counts)
        end
        valid || throw(ArgumentError("invalid warmup diagnostic coverage or event counts"))
    end
    return copy(rows)
end

function _store_sampler_draw!(draws::Matrix{Float64}, logps::Vector{Float64},
        values, stat::NamedTuple, row::Int)
    length(values) == size(draws, 2) || throw(ArgumentError(
        "chain $(stat.chain) retained draw $(stat.iteration) has $(length(values)) parameters; expected $(size(draws, 2))"))
    draws[row, :] .= values
    all(isfinite, @view draws[row, :]) || throw(ArgumentError(
        "chain $(stat.chain) retained draw $(stat.iteration) contains non-finite parameters"))
    logps[row] = stat.log_density
    isfinite(logps[row]) || throw(ArgumentError(
        "chain $(stat.chain) retained draw $(stat.iteration) has non-finite log density"))
    return nothing
end

function _turing_metric_type(metric::Symbol)
    metric === :diagonal && return AdvancedHMC.DiagEuclideanMetric
    metric === :unit && return AdvancedHMC.UnitEuclideanMetric
    metric === :dense && return AdvancedHMC.DenseEuclideanMetric
    throw(ArgumentError("metric must be :diagonal, :unit, or :dense"))
end

function _check_turing_ad_backend(ad_backend::Symbol)
    ad_backend === :ForwardDiff && return nothing
    ad_backend === :ReverseDiff &&
        throw(ArgumentError("ad_backend = :ReverseDiff is not supported for backend = :turing"))
    ad_backend === :analytic &&
        throw(ArgumentError("ad_backend = :analytic is not supported for backend = :turing"))
    throw(ArgumentError("ad_backend must be :ForwardDiff for backend = :turing"))
end

# Keep cache scheduling independent of whether the optional sampler is loaded.
_turing_discard_initial(warmup::Int) = warmup + 1

function _fit_turing(args...; kwargs...)
    extension = Base.get_extension(@__MODULE__, :BayesianMGMFRMTuringExt)
    extension === nothing && throw(ArgumentError(
        "backend = :turing requires `import Turing` before fitting. If needed, install the optional package with `Pkg.add(\"Turing\")` in your analysis environment."))
    return extension.fit_turing(args...; kwargs...)
end

function _stat_mean(rows, field::Symbol)
    values = Float64[]
    for row in rows
        value = getproperty(row, field)
        ismissing(value) && continue
        isfinite(value) && push!(values, Float64(value))
    end
    isempty(values) && return NaN
    return _column_mean(values)
end

function _fit_advancedhmc(design::FacetDesign,
        prior::MFRMPrior,
        ndraws::Int,
        warmup::Int,
        chains::Int,
        step::Float64,
        initial::Vector{Float64},
        rng::AbstractRNG,
        rng_control::NamedTuple;
        target_accept::Real,
        max_depth::Int,
        max_energy_error::Real,
        metric::Symbol,
        ad_backend::Symbol,
        init_jitter::Real,
        progress::Union{Bool,SamplingProgress},
        record_warmup::Bool = false,
        chain_execution::Symbol = :serial,
        max_parallel_chains::Int = chains)
    target_accept, max_energy_error, init_jitter =
        _check_nuts_controls(target_accept, max_depth, max_energy_error, init_jitter)
    gradient_backend = _gradient_backend_kind(ad_backend)

    nparams = length(design.parameter_names)
    nparams >= 1 || throw(ArgumentError("at least one parameter is required for AdvancedHMC fitting"))
    total_draws = ndraws * chains
    draws = Matrix{Float64}(undef, total_draws, nparams)
    logps = Vector{Float64}(undef, total_draws)
    chain_ids = Vector{Int}(undef, total_draws)
    iterations = Vector{Int}(undef, total_draws)
    chain_acceptance = Vector{Float64}(undef, chains)
    stats_by_chain = [NamedTuple[] for _ in 1:chains]
    warmup_by_chain = record_warmup ? [NamedTuple[] for _ in 1:chains] : nothing
    target = MFRMLogDensity(design; prior)
    controls = (;
        ndraws,
        warmup,
        chains,
        step_size = step,
        target_accept = Float64(target_accept),
        max_depth,
        max_energy_error = Float64(max_energy_error),
        metric,
        ad_backend,
        gradient_backend,
        rng = rng_control,
        init_jitter = Float64(init_jitter),
    )

    schedule = _sampling_chain_schedule(rng, chains, chain_execution, max_parallel_chains)
    controls = merge(controls, schedule.metadata)
    progress = _threaded_progress(progress, schedule.mode)
    observer_guard = ReentrantLock()
    _with_sampling_progress(progress, chains, warmup, ndraws) do
        _foreach_sampling_chain(schedule, chains, rng) do chain, chain_rng, cancelled
            chain_target = schedule.mode === :threads ? deepcopy(target) : target
            _progress_chain!(progress, chain, warmup, ndraws)
            chain_initial = _with_sampler_context(:advancedhmc, chain, :initialization) do
                values = _advancedhmc_initial(initial, chain_rng, Float64(init_jitter))
                current_lp = logposterior(design, values, prior)
                isfinite(current_lp) || throw(ArgumentError("initial parameter vector has non-finite log posterior"))
                values
            end
            gradient_target = _with_sampler_context(:advancedhmc, chain, :initialization) do
                _logdensity_gradient_target(chain_target, chain_initial, ad_backend).target
            end
            metric_object = _advancedhmc_metric(metric, nparams)
            hamiltonian = AdvancedHMC.Hamiltonian(
                metric_object,
                x -> LogDensityProblems.logdensity(gradient_target, x),
                x -> LogDensityProblems.logdensity_and_gradient(gradient_target, x),
            )
            integrator = AdvancedHMC.Leapfrog(step)
            kernel = AdvancedHMC.HMCKernel(AdvancedHMC.Trajectory{AdvancedHMC.MultinomialTS}(
                integrator,
                AdvancedHMC.GeneralisedNoUTurn(max_depth, Float64(max_energy_error)),
            ))
            adaptor = warmup > 0 ?
                AdvancedHMC.StanHMCAdaptor(
                    AdvancedHMC.MassMatrixAdaptor(metric_object),
                    AdvancedHMC.StepSizeAdaptor(Float64(target_accept), integrator),
                ) :
                AdvancedHMC.NoAdaptation()
            samples, stats = _with_sampler_context(:advancedhmc, chain, :sampling) do
                AdvancedHMC.sample(
                    chain_rng,
                    hamiltonian,
                    kernel,
                    chain_initial,
                    warmup + ndraws,
                    adaptor,
                    warmup;
                    drop_warmup = warmup > 0 && !record_warmup,
                    verbose = false,
                    _advancedhmc_progress_options(progress, chain, warmup, ndraws,
                        _sampling_chain_observer(nothing, cancelled, observer_guard))...,
                )
            end
            _with_sampler_context(:advancedhmc, chain, :output_validation) do
                offset = record_warmup ? warmup : 0
                expected = ndraws + offset
                length(samples) == expected ||
                    throw(ArgumentError("chain $chain: AdvancedHMC returned $(length(samples)) draw(s); expected $expected"))
                length(stats) == expected ||
                    throw(ArgumentError("chain $chain: AdvancedHMC returned $(length(stats)) sampler-stat row(s); expected $expected"))
                for iteration in 1:offset
                    push!(warmup_by_chain[chain], _warmup_stat_row(stats[iteration], chain, iteration))
                end
                chain_stats = stats_by_chain[chain]
                for iteration in 1:ndraws
                    row = (chain - 1) * ndraws + iteration
                    stat_row = _advancedhmc_stat_row(stats[offset + iteration], chain, iteration)
                    _store_sampler_draw!(draws, logps, samples[offset + iteration], stat_row, row)
                    chain_ids[row] = chain
                    iterations[row] = iteration
                    push!(chain_stats, stat_row)
                end
                chain_acceptance[chain] = _stat_mean(chain_stats, :acceptance_rate)
            end
        end
    end

    sampler_stats = reduce(vcat, stats_by_chain)
    warmup_stats = record_warmup ? reduce(vcat, warmup_by_chain) : nothing

    return MFRMFit(design, prior, draws, logps, _column_mean(chain_acceptance),
        chain_ids, iterations, chain_acceptance, :advancedhmc, :nuts, warmup,
        _stat_mean(sampler_stats, :step_size), sampler_stats,
        _with_warmup_diagnostics(controls, warmup_stats, :advancedhmc))
end

function _fit_draws_per_chain(fit::MFRMFit)
    nchains = length(fit.chain_acceptance_rate)
    nchains >= 1 || throw(ArgumentError("fit has no chain metadata"))
    total = size(fit.draws, 1)
    total == length(fit.chain_ids) == length(fit.iterations) == length(fit.log_posterior) ||
        throw(ArgumentError("fit draw metadata length does not match draws"))
    total % nchains == 0 ||
        throw(ArgumentError("fit has uneven chain draw counts"))
    draws_per_chain = div(total, nchains)
    for chain in 1:nchains
        rows = ((chain - 1) * draws_per_chain + 1):(chain * draws_per_chain)
        all(==(chain), @view fit.chain_ids[rows]) ||
            throw(ArgumentError("fit draws are not grouped by chain"))
        all(fit.iterations[row] == row - first(rows) + 1 for row in rows) ||
            throw(ArgumentError("fit iterations are not consecutive within chain"))
    end
    return draws_per_chain
end

function _fit_draws_per_chain(fit::GMFRMFit)
    nchains = length(fit.chain_acceptance_rate)
    nchains >= 1 || throw(ArgumentError("fit has no chain metadata"))
    total = size(fit.draws, 1)
    total == length(fit.chain_ids) == length(fit.iterations) == length(fit.log_posterior) ||
        throw(ArgumentError("fit draw metadata length does not match draws"))
    total % nchains == 0 ||
        throw(ArgumentError("fit has uneven chain draw counts"))
    draws_per_chain = div(total, nchains)
    for chain in 1:nchains
        rows = ((chain - 1) * draws_per_chain + 1):(chain * draws_per_chain)
        all(==(chain), @view fit.chain_ids[rows]) ||
            throw(ArgumentError("fit draws are not grouped by chain"))
        all(fit.iterations[row] == row - first(rows) + 1 for row in rows) ||
            throw(ArgumentError("fit iterations are not consecutive within chain"))
    end
    return draws_per_chain
end

function _fit_draws_per_chain(fit::MGMFRMFit)
    nchains = length(fit.chain_acceptance_rate)
    nchains >= 1 || throw(ArgumentError("fit has no chain metadata"))
    total = size(fit.draws, 1)
    total == length(fit.chain_ids) == length(fit.iterations) == length(fit.log_posterior) ||
        throw(ArgumentError("fit draw metadata length does not match draws"))
    total % nchains == 0 ||
        throw(ArgumentError("fit has uneven chain draw counts"))
    draws_per_chain = div(total, nchains)
    for chain in 1:nchains
        rows = ((chain - 1) * draws_per_chain + 1):(chain * draws_per_chain)
        all(==(chain), @view fit.chain_ids[rows]) ||
            throw(ArgumentError("fit draws are not grouped by chain"))
        all(fit.iterations[row] == row - first(rows) + 1 for row in rows) ||
            throw(ArgumentError("fit iterations are not consecutive within chain"))
    end
    return draws_per_chain
end

function _chain_draw_array(fit::MFRMFit)
    draws_per_chain = _fit_draws_per_chain(fit)
    nchains = length(fit.chain_acceptance_rate)
    nparams = size(fit.draws, 2)
    out = Array{Float64}(undef, draws_per_chain, nchains, nparams)
    for chain in 1:nchains
        rows = ((chain - 1) * draws_per_chain + 1):(chain * draws_per_chain)
        for param in 1:nparams
            out[:, chain, param] .= fit.draws[rows, param]
        end
    end
    return out
end

function _split_chain_array(values::Array{Float64,3})
    niterations, nchains, nparams = size(values)
    if niterations < 4
        return values
    end
    half = div(niterations, 2)
    out = Array{Float64}(undef, half, 2 * nchains, nparams)
    for chain in 1:nchains
        out[:, 2 * chain - 1, :] .= values[1:half, chain, :]
        out[:, 2 * chain, :] .= values[(niterations - half + 1):niterations, chain, :]
    end
    return out
end

function _chain_variance(values::AbstractVector{<:Real})
    n = length(values)
    n <= 1 && return NaN
    mean_value = _column_mean(values)
    ss = 0.0
    for value in values
        d = Float64(value) - mean_value
        ss += d * d
    end
    return ss / (n - 1)
end

function _rhat_and_ess(values::Array{Float64,3}, param::Int)
    niterations, nchains, _ = size(values)
    total_draws = niterations * nchains
    if nchains < 2 || niterations < 2
        return (rhat = NaN, ess = NaN, flag = :insufficient_chains)
    end

    chain_means = Vector{Float64}(undef, nchains)
    chain_vars = Vector{Float64}(undef, nchains)
    for chain in 1:nchains
        vals = @view values[:, chain, param]
        chain_means[chain] = _column_mean(vals)
        chain_vars[chain] = _chain_variance(vals)
    end
    W = _column_mean(chain_vars)
    B = niterations * _chain_variance(chain_means)
    if !(isfinite(W) && isfinite(B)) || W < 0 || B < 0
        return (rhat = NaN, ess = NaN, flag = :degenerate_draws)
    end
    if W == 0
        rhat = B == 0 ? 1.0 : Inf
        ess = B == 0 ? Float64(total_draws) : NaN
        flag = isfinite(rhat) ? :ok : :degenerate_draws
        return (rhat = rhat, ess = ess, flag = flag)
    end

    var_plus = ((niterations - 1) / niterations) * W + B / niterations
    rhat = sqrt(max(var_plus / W, 0.0))
    # Later lag pairs cannot contribute after the first nonpositive pair.
    # Keep each covariance and pair sum in the original arithmetic order.
    function autocorrelation(lag)
        autocov = 0.0
        for chain in 1:nchains
            mean_value = chain_means[chain]
            s = 0.0
            for iteration in 1:(niterations - lag)
                s += (values[iteration, chain, param] - mean_value) *
                    (values[iteration + lag, chain, param] - mean_value)
            end
            autocov += s / (niterations - 1)
        end
        return autocov / (nchains * W)
    end
    positive_sum = 0.0
    max_lag = niterations - 1
    lag = 1
    while lag <= max_lag
        first = autocorrelation(lag)
        if lag == max_lag
            first > 0 && (positive_sum += first)
            break
        end
        pair_sum = first + autocorrelation(lag + 1)
        pair_sum > 0 || break
        positive_sum += pair_sum
        lag += 2
    end
    tau = max(1.0, 1 + 2 * positive_sum)
    ess = clamp(total_draws / tau, 1.0, Float64(total_draws))
    flag = isfinite(rhat) && isfinite(ess) ? :ok : :degenerate_draws
    return (rhat = rhat, ess = ess, flag = flag)
end

const _RANK_NORMALIZED_TAIL_PROBABILITY = 0.10
const _MCMC_DIAGNOSTIC_CONTRACT =
    :rank_normalized_rhat_bulk_tail_ess_v1

_mcmc_diagnostic_method(split_chains::Bool) = split_chains ?
    :rank_normalized_split_rhat_bulk_tail_ess :
    :rank_normalized_unsplit_rhat_bulk_tail_ess

function _mcmc_diagnostic_contract_record()
    return (;
        id = _MCMC_DIAGNOSTIC_CONTRACT,
        dependency = (;
            package = :MCMCDiagnosticTools,
            version = string(pkgversion(MCMCDiagnosticTools)),
        ),
        minimum_independent_chains = 2,
        split_factor = 2,
        split_request_field = :split_chains_requested,
        split_applied_field = :split_chains,
        diagnostic_methods = (;
            split = _mcmc_diagnostic_method(true),
            unsplit = _mcmc_diagnostic_method(false),
        ),
        odd_draw_policy = :bulk_trim_fold_before_trim_tail_quantile_before_split,
        tail_probability = _RANK_NORMALIZED_TAIL_PROBABILITY,
        autocovariance_maxlag_policy = :all_available_lags,
        minimum_draws_per_diagnostic_chain_for_ess = 5,
        nonfinite_input_policy = :precheck_before_rank_normalization,
        quality_gate = (;
            applicability_field = :quality_gate_applicable,
            structurally_fixed_status = :structurally_fixed,
            structurally_fixed_policy =
                :exclude_zero_raw_dimension_transforms,
        ),
        sampler_fields = (;
            e_bfmi = :e_bfmi,
            e_bfmi_expected = :n_e_bfmi_expected,
            e_bfmi_available = :n_e_bfmi_available,
            e_bfmi_unavailable = :n_e_bfmi_unavailable,
            e_bfmi_complete = :e_bfmi_complete,
            e_bfmi_input_policy =
                :all_retained_chain_energies_finite,
            complete_chain_coverage_required = true,
        ),
        primary_fields = (;
            rhat = :rank_normalized_rhat,
            ess = (:bulk_ess, :tail_ess),
            flag = :rank_normalized_flag,
        ),
        compatibility_fields = (;
            rhat = :rhat,
            ess = :ess,
            flag = :classical_compatibility_flag,
        ),
    )
end

function _rank_normalized_rhat_bulk_tail_ess(
        values::Array{Float64,3},
        param::Int;
        split_chains::Bool)
    niterations, nchains, _ = size(values)
    nan_result(flag) = (;
        rank_normalized_rhat = NaN,
        bulk_rank_normalized_rhat = NaN,
        folded_rank_normalized_rhat = NaN,
        bulk_ess = NaN,
        tail_ess = NaN,
        tail_probability = _RANK_NORMALIZED_TAIL_PROBABILITY,
        autocovariance_maxlag = missing,
        flag,
    )
    nchains >= 2 || return nan_result(:insufficient_chains)
    niterations >= 2 || return nan_result(:insufficient_draws)
    original_samples = Matrix{Float64}(@view values[:, :, param])
    all(isfinite, original_samples) || return nan_result(:nonfinite_draws)
    split_chains && niterations < 4 &&
        return nan_result(:insufficient_draws)

    split_count = split_chains ? 2 : 1
    bulk_samples = if split_count == 2 && isodd(niterations)
        half = div(niterations, 2)
        vcat(
            @view(original_samples[1:half, :]),
            @view(original_samples[(niterations - half + 1):niterations, :]),
        )
    else
        original_samples
    end
    diagnostic_iterations = div(size(bulk_samples, 1), split_count)
    diagnostic_iterations >= 2 || return nan_result(:insufficient_draws)
    folded_samples = abs.(original_samples .- median(vec(original_samples)))
    folded_samples = if split_count == 2 && isodd(niterations)
        half = div(niterations, 2)
        vcat(
            @view(folded_samples[1:half, :]),
            @view(folded_samples[(niterations - half + 1):niterations, :]),
        )
    else
        folded_samples
    end
    folded_rank_normalized_rhat = Float64(MCMCDiagnosticTools.rhat(
        folded_samples;
        kind = :bulk,
        split_chains = split_count,
    ))
    if diagnostic_iterations <= 4
        bulk_rank_normalized_rhat = Float64(MCMCDiagnosticTools.rhat(
            bulk_samples;
            kind = :bulk,
            split_chains = split_count,
        ))
        if !(isfinite(bulk_rank_normalized_rhat) &&
                isfinite(folded_rank_normalized_rhat))
            return nan_result(:degenerate_draws)
        end
        rank_normalized_rhat = max(
            bulk_rank_normalized_rhat,
            folded_rank_normalized_rhat,
        )
        return (;
            rank_normalized_rhat,
            bulk_rank_normalized_rhat,
            folded_rank_normalized_rhat,
            bulk_ess = NaN,
            tail_ess = NaN,
            tail_probability = _RANK_NORMALIZED_TAIL_PROBABILITY,
            autocovariance_maxlag = missing,
            flag = :insufficient_draws,
        )
    end

    maxlag = diagnostic_iterations - 4
    bulk = MCMCDiagnosticTools.ess_rhat(
        bulk_samples;
        kind = :bulk,
        split_chains = split_count,
        maxlag,
    )
    bulk_ess = Float64(bulk.ess)
    bulk_rank_normalized_rhat = Float64(bulk.rhat)
    if !(isfinite(bulk_rank_normalized_rhat) &&
            isfinite(folded_rank_normalized_rhat))
        return nan_result(:degenerate_draws)
    end
    rank_normalized_rhat = max(
        bulk_rank_normalized_rhat,
        folded_rank_normalized_rhat,
    )
    tail_ess = Float64(MCMCDiagnosticTools.ess(
        original_samples;
        kind = :tail,
        tail_prob = _RANK_NORMALIZED_TAIL_PROBABILITY,
        split_chains = split_count,
        maxlag,
    ))
    flag = isfinite(bulk_ess) && isfinite(tail_ess) ?
        :ok : :degenerate_draws
    return (;
        rank_normalized_rhat,
        bulk_rank_normalized_rhat,
        folded_rank_normalized_rhat,
        bulk_ess,
        tail_ess,
        tail_probability = _RANK_NORMALIZED_TAIL_PROBABILITY,
        autocovariance_maxlag = maxlag,
        flag,
    )
end

function _mcmc_parameter_metrics(
        values::Array{Float64,3},
        param::Int;
        split_chains::Bool)
    original_iterations, original_chains, _ = size(values)
    actual_split = split_chains && original_chains >= 2 &&
        original_iterations >= 4
    # Copy only this parameter; copying the entire cube here scales quadratically.
    classical_values = actual_split ? _split_chain_array(values[:, :, param:param]) : values
    classical = _rhat_and_ess(classical_values, actual_split ? 1 : param)
    modern = _rank_normalized_rhat_bulk_tail_ess(
        values,
        param;
        split_chains,
    )
    finite_draws = all(isfinite, @view values[:, :, param])
    classical_compatibility_status = finite_draws ?
        classical.flag : :nonfinite_draws
    return (;
        rhat = classical.rhat,
        ess = classical.ess,
        rank_normalized_rhat = modern.rank_normalized_rhat,
        bulk_rank_normalized_rhat = modern.bulk_rank_normalized_rhat,
        folded_rank_normalized_rhat = modern.folded_rank_normalized_rhat,
        bulk_ess = modern.bulk_ess,
        tail_ess = modern.tail_ess,
        tail_probability = modern.tail_probability,
        autocovariance_maxlag = modern.autocovariance_maxlag,
        rank_normalized_status = modern.flag,
        classical_compatibility_status,
        flag = modern.flag,
    )
end

function _draw_matrix_to_chain_array(draws::AbstractMatrix{<:Real}, chains::Int)
    chains >= 1 || throw(ArgumentError("chains must be positive"))
    total_draws, nparams = size(draws)
    total_draws % chains == 0 ||
        throw(ArgumentError("draw matrix has uneven chain draw counts"))
    draws_per_chain = div(total_draws, chains)
    out = Array{Float64}(undef, draws_per_chain, chains, nparams)
    for chain in 1:chains
        rows = ((chain - 1) * draws_per_chain + 1):(chain * draws_per_chain)
        for param in 1:nparams
            out[:, chain, param] .= Float64.(@view draws[rows, param])
        end
    end
    return out
end

function _structurally_fixed_constrained_parameter_names(blueprint)
    names = Set{String}()
    for transform in _source_transform_manifest_rows(blueprint)
        transform.raw_n_parameters == 0 || continue
        transform.constrained_n_parameters > 0 || continue
        union!(names, transform.constrained_parameter_names)
    end
    return names
end

function _candidate_mcmc_diagnostic_rows(draws::AbstractMatrix{<:Real},
        parameter_names::Vector{String},
        chains::Int;
        parameter_space::Symbol = :raw_unconstrained,
        structurally_fixed_parameters = Set{String}(),
        split_chains::Bool,
        rhat_threshold::Float64,
        ess_threshold::Float64)
    values = _draw_matrix_to_chain_array(draws, chains)
    original_iterations, original_chains, nparams = size(values)
    length(parameter_names) == nparams ||
        throw(ArgumentError("parameter name count does not match draw columns"))
    actual_split = split_chains && original_chains >= 2 && original_iterations >= 4
    # Metrics split one parameter at a time; only the full split's shape is needed here.
    diagnostic_iterations = actual_split ? div(original_iterations, 2) : original_iterations
    diagnostic_chains = actual_split ? 2 * original_chains : original_chains
    rows = NamedTuple[]
    for param in 1:nparams
        parameter = parameter_names[param]
        quality_gate_applicable =
            !(parameter in structurally_fixed_parameters)
        diagnostic = if quality_gate_applicable
            _mcmc_parameter_metrics(
                values,
                param;
                split_chains,
            )
        else
            (;
                rhat = NaN,
                ess = NaN,
                rank_normalized_rhat = NaN,
                bulk_rank_normalized_rhat = NaN,
                folded_rank_normalized_rhat = NaN,
                bulk_ess = NaN,
                tail_ess = NaN,
                tail_probability = _RANK_NORMALIZED_TAIL_PROBABILITY,
                autocovariance_maxlag = missing,
                rank_normalized_status = :structurally_fixed,
                classical_compatibility_status = :structurally_fixed,
                flag = :structurally_fixed,
            )
        end
        rank_normalized_flag = quality_gate_applicable ?
            _mcmc_parameter_flag(
                diagnostic,
                rhat_threshold,
                ess_threshold,
            ) : :structurally_fixed
        classical_compatibility_flag = quality_gate_applicable ?
            _classical_compatibility_parameter_flag(
                diagnostic,
                rhat_threshold,
                ess_threshold,
            ) : :structurally_fixed
        push!(rows, (;
            diagnostic_row = :parameter,
            parameter_space,
            diagnostic_contract = _MCMC_DIAGNOSTIC_CONTRACT,
            diagnostic_method = _mcmc_diagnostic_method(split_chains),
            diagnostic_status = quality_gate_applicable ?
                :rank_normalized_available : :structurally_fixed,
            parameter,
            quality_gate_applicable,
            rhat = diagnostic.rhat,
            ess = diagnostic.ess,
            rank_normalized_rhat = diagnostic.rank_normalized_rhat,
            bulk_rank_normalized_rhat =
                diagnostic.bulk_rank_normalized_rhat,
            folded_rank_normalized_rhat =
                diagnostic.folded_rank_normalized_rhat,
            bulk_ess = diagnostic.bulk_ess,
            tail_ess = diagnostic.tail_ess,
            tail_probability = diagnostic.tail_probability,
            autocovariance_maxlag = diagnostic.autocovariance_maxlag,
            n_chains = original_chains,
            draws_per_chain = original_iterations,
            diagnostic_chains,
            diagnostic_draws_per_chain = diagnostic_iterations,
            total_draws = size(draws, 1),
            split_chains_requested = split_chains,
            split_chains = actual_split,
            rank_normalized_flag,
            classical_compatibility_flag,
            flag = rank_normalized_flag,
        ))
    end
    return rows
end

function _candidate_parameter_block_diagnostics(blocks::Dict{Symbol,UnitRange{Int}},
        parameter_names::Vector{String},
        parameter_rows;
        parameter_space::Symbol = :raw_unconstrained,
        chains::Int,
        draws_per_chain::Int,
        total_draws::Int,
        split_chains::Bool,
        split_chains_requested::Bool = split_chains,
        rhat_threshold::Float64,
        ess_threshold::Float64)
    row_by_name = Dict(row.parameter => row for row in parameter_rows)
    rows = NamedTuple[]
    for block in sort(collect(keys(blocks)); by = string)
        range = blocks[block]
        indices = collect(range)
        names = isempty(indices) ? String[] : copy(parameter_names[indices])
        block_rows = [row_by_name[name] for name in names]
        n_parameters = length(names)
        metrics = _mcmc_metric_summary(
            block_rows,
            rhat_threshold,
            ess_threshold,
        )
        n_quality_gate_parameters = metrics.n_quality_gate_parameters
        n_structurally_fixed_parameters =
            metrics.n_structurally_fixed_parameters
        quality_gate_applicable = n_quality_gate_parameters > 0
        available_rows = filter(row -> row.quality_gate_applicable, block_rows)
        push!(rows, (;
            diagnostic_row = :parameter_block,
            parameter_space,
            diagnostic_contract = _MCMC_DIAGNOSTIC_CONTRACT,
            diagnostic_method =
                _mcmc_diagnostic_method(split_chains_requested),
            diagnostic_status = n_parameters > 0 &&
                !quality_gate_applicable ?
                :structurally_fixed : :rank_normalized_available,
            block,
            first_parameter = isempty(indices) ? missing : first(indices),
            last_parameter = isempty(indices) ? missing : last(indices),
            n_parameters,
            n_quality_gate_parameters,
            n_structurally_fixed_parameters,
            quality_gate_applicable,
            parameter_names = names,
            n_chains = chains,
            draws_per_chain,
            total_draws,
            split_chains_requested,
            split_chains,
            autocovariance_maxlag = isempty(available_rows) ? missing :
                first(available_rows).autocovariance_maxlag,
            rhat_threshold,
            ess_threshold,
            max_rhat = !quality_gate_applicable ? missing : metrics.max_rhat,
            min_ess = !quality_gate_applicable ? missing : metrics.min_ess,
            max_rank_normalized_rhat = !quality_gate_applicable ? missing :
                metrics.max_rank_normalized_rhat,
            min_bulk_ess = !quality_gate_applicable ? missing :
                metrics.min_bulk_ess,
            min_tail_ess = !quality_gate_applicable ? missing :
                metrics.min_tail_ess,
            n_bad_rhat = metrics.n_bad_rhat,
            n_low_ess = metrics.n_low_ess,
            n_bad_rank_normalized_rhat =
                metrics.n_bad_rank_normalized_rhat,
            n_low_bulk_ess = metrics.n_low_bulk_ess,
            n_low_tail_ess = metrics.n_low_tail_ess,
            n_insufficient_chains = metrics.n_insufficient_chains,
            n_insufficient_draws = metrics.n_insufficient_draws,
            n_nonfinite_parameters = metrics.n_nonfinite_parameters,
            n_degenerate_parameters = metrics.n_degenerate_parameters,
            classical_compatibility_flag =
                _classical_compatibility_block_flag(n_parameters, metrics),
            rank_normalized_flag =
                _parameter_block_flag(n_parameters, metrics),
            flag = _parameter_block_flag(n_parameters, metrics),
        ))
    end
    return rows
end

function _candidate_chain_sampler_summary(rows, max_depth::Int)
    return (;
        n_divergences = _maybe_count(rows, row -> row.numerical_error),
        n_max_treedepth =
            _maybe_count(rows, row -> !ismissing(row.tree_depth) && row.tree_depth >= max_depth),
        mean_n_steps = _maybe_mean(rows, :n_steps),
        mean_tree_depth = _maybe_mean(rows, :tree_depth),
        max_tree_depth = _maybe_max_int(rows, :tree_depth),
        mean_step_size = _maybe_mean(rows, :step_size),
        e_bfmi = _ebfmi((row.hamiltonian_energy for row in rows)),
    )
end

function _generalized_candidate_sampler_rows(
        logdensities::AbstractVector,
        iterations::AbstractVector{<:Integer},
        chain_acceptance::AbstractVector,
        sampler_stats,
        controls::NamedTuple,
        backend::Symbol;
        sampler::Symbol = :nuts)
    rows = NamedTuple[]
    for chain in 1:controls.chains
        draw_rows = ((chain - 1) * controls.ndraws + 1):(chain * controls.ndraws)
        logps = @view logdensities[draw_rows]
        logdensity_summary = _finite_log_posterior_summary(logps)
        n_finite = count(isfinite, logps)
        n_nonfinite = length(logps) - n_finite
        chain_stats = [row for row in sampler_stats if row.chain == chain]
        sampler_summary = _candidate_chain_sampler_summary(
            chain_stats,
            controls.max_depth,
        )
        push!(rows, (;
            diagnostic_row = :sampler_chain,
            parameter_space = :raw_unconstrained,
            diagnostic_method = :sampler_chain_summary,
            diagnostic_status = :recorded,
            chain,
            backend,
            sampler,
            n_draws = controls.ndraws,
            warmup = controls.warmup,
            step_size = Float64(controls.step_size),
            first_iteration = first(@view iterations[draw_rows]),
            last_iteration = last(@view iterations[draw_rows]),
            acceptance_rate = chain_acceptance[chain],
            mean_logdensity = logdensity_summary.mean,
            minimum_logdensity = logdensity_summary.minimum,
            maximum_logdensity = logdensity_summary.maximum,
            n_finite_logdensity = n_finite,
            n_nonfinite_logdensity = n_nonfinite,
            n_divergences = sampler_summary.n_divergences,
            n_max_treedepth = sampler_summary.n_max_treedepth,
            mean_n_steps = sampler_summary.mean_n_steps,
            mean_tree_depth = sampler_summary.mean_tree_depth,
            max_tree_depth = sampler_summary.max_tree_depth,
            mean_step_size = sampler_summary.mean_step_size,
            e_bfmi = sampler_summary.e_bfmi,
            flag = _sampler_diagnostic_flag(
                chain_acceptance[chain],
                n_nonfinite,
                sampler_summary.n_divergences,
                sampler_summary.n_max_treedepth,
            ),
        ))
    end
    return rows
end

function _gmfrm_candidate_direct_draw_values(
        target::_GMFRMPromotionCandidateLogDensity,
        raw_draws::AbstractMatrix{<:Real})
    n_draws = size(raw_draws, 1)
    n_direct = length(target.blueprint.constrained_parameter_names)
    n_observations = target.design.spec.data.n
    direct_draws = Matrix{Float64}(undef, n_draws, n_direct)
    pointwise = Matrix{Float64}(undef, n_draws, n_observations)
    loglikelihood = Vector{Float64}(undef, n_draws)
    for draw in 1:n_draws
        raw = collect(@view raw_draws[draw, :])
        direct = _gmfrm_source_constrained_params_from_unconstrained(target.design, raw)
        direct_pointwise = _gmfrm_source_pointwise_loglikelihood(target.design, direct)
        direct_draws[draw, :] .= direct
        pointwise[draw, :] .= direct_pointwise
        loglikelihood[draw] = sum(direct_pointwise; init = 0.0)
    end
    return (;
        direct_draws,
        pointwise_loglikelihood = pointwise,
        loglikelihood,
    )
end

function _gmfrm_candidate_direct_draw_constraint_rows(
        design::FacetDesign,
        direct_draws::AbstractMatrix{<:Real})
    n_draws = size(direct_draws, 1)
    n_draws == 0 && return NamedTuple[]
    template = _gmfrm_direct_constraint_rows(design, @view direct_draws[1, :])
    values = [Float64[] for _ in template]
    n_failed = zeros(Int, length(template))
    for draw in 1:n_draws
        rows = _gmfrm_direct_constraint_rows(design, @view direct_draws[draw, :])
        length(rows) == length(template) ||
            throw(ArgumentError("direct constraint row count changed across draws"))
        for index in eachindex(rows)
            rows[index].constraint === template[index].constraint &&
                rows[index].block === template[index].block ||
                throw(ArgumentError("direct constraint row identity changed across draws"))
            push!(values[index], Float64(rows[index].value))
            rows[index].passed || (n_failed[index] += 1)
        end
    end
    rows = NamedTuple[]
    for index in eachindex(template)
        row_values = values[index]
        target = Float64(template[index].target)
        push!(rows, (;
            constraint_index = index,
            constraint = template[index].constraint,
            block = template[index].block,
            target,
            tolerance = Float64(template[index].tolerance),
            n_draws,
            n_failed = n_failed[index],
            minimum_value = minimum(row_values),
            maximum_value = maximum(row_values),
            max_abs_target_error =
                maximum(abs(value - target) for value in row_values),
            passed = n_failed[index] == 0,
        ))
    end
    return rows
end

function _mgmfrm_direct_constraint_rows(design::FacetDesign, direct_params::AbstractVector)
    data = design.spec.data
    rater_values = direct_params[design.blocks[:rater]]
    item_dimension_discrimination_values =
        direct_params[design.blocks[:item_dimension_discrimination]]
    rater_consistency_values = direct_params[design.blocks[:rater_consistency]]
    consistency_product = _positive_product(rater_consistency_values)
    item_step_values = direct_params[design.blocks[:item_steps]]
    rows = [
        (constraint = :rater_sum_to_zero, block = :rater,
            value = Float64(sum(rater_values)), target = 0.0,
            tolerance = 1e-8, passed = abs(sum(rater_values)) <= 1e-8),
        (constraint = :item_dimension_discrimination_positive,
            block = :item_dimension_discrimination,
            value = Float64(minimum(item_dimension_discrimination_values)),
            target = 0.0,
            tolerance = 0.0,
            passed = all(>(0), item_dimension_discrimination_values)),
        (constraint = :rater_consistency_positive, block = :rater_consistency,
            value = Float64(minimum(rater_consistency_values)), target = 0.0,
            tolerance = 0.0, passed = all(>(0), rater_consistency_values)),
        (constraint = :rater_consistency_product_one, block = :rater_consistency,
            value = Float64(consistency_product), target = 1.0,
            tolerance = 1e-8,
            passed = abs(consistency_product - 1) <= 1e-8),
    ]
    if length(data.category_levels) >= 3 && !isempty(item_step_values)
        free_steps = max(length(data.category_levels) - 2, 0)
        for item_index in eachindex(data.item_levels)
            step_sum = sum(item_step_values[((item_index - 1) * free_steps + 1):(item_index * free_steps)];
                init = _param_zero(direct_params))
            push!(rows, (constraint = :item_step_last_derived_sum_to_zero,
                block = :item_steps,
                value = Float64(step_sum + (-step_sum)),
                target = 0.0,
                tolerance = 1e-8,
                passed = true))
        end
    end
    return rows
end

function _mgmfrm_ability_prior_metadata(prior::Union{Nothing,_SourceFixturePrior})
    sd = prior === nothing ? missing : prior.person_sd
    return (;
        ability_scale = prior === nothing ? missing :
            sd == 1.0 ? :standard_normal_by_dimension : :normal_by_dimension,
        ability_prior = (;
            distribution = :normal, mean = 0.0, sd,
            independent_dimensions = true,
            conditioning = :fixed_prior_hyperparameters,
            status = prior === nothing ? :not_recorded : :resolved_from_prior,
        ),
    )
end

function _mgmfrm_confirmatory_candidate_pointwise_fixture(
        design::FacetDesign,
        direct_params::AbstractVector)
    _check_mgmfrm_source_fixture_design(design, "_mgmfrm_confirmatory_candidate_pointwise_fixture")
    design.spec.dimensions >= 1 ||
        throw(ArgumentError("_mgmfrm_confirmatory_candidate_pointwise_fixture requires dimensions >= 1"))
    _check_parameter_vector_length(design, direct_params)
    _mgmfrm_source_fixture_constraints(design, direct_params)
    direct = Float64.(collect(direct_params))
    rows = _mgmfrm_source_fixture_values(design, direct)
    pointwise = [Float64(row.log_probability) for row in rows if row.observed]
    constraint_rows = _mgmfrm_direct_constraint_rows(design, direct)
    n_failed_constraints = count(row -> !row.passed, constraint_rows)
    loglikelihood = sum(pointwise; init = 0.0)
    passed = length(pointwise) == design.spec.data.n && n_failed_constraints == 0 &&
        all(isfinite, pointwise)
    return (;
        schema = "bayesianmgmfrm.mgmfrm_confirmatory_candidate_pointwise_fixture.v1",
        family = :mgmfrm,
        scope = :minimal_confirmatory_mgmfrm_candidate,
        status = :internal_fit_ready_candidate,
        public_fit = false,
        fit_ready = false,
        density_space = :constrained_direct,
        q_matrix = _q_matrix_manifest(design.spec.q_matrix),
        latent_correlation = :identity_fixed,
        _mgmfrm_ability_prior_metadata(nothing)...,
        parameter_layout = fit_ready_parameter_layout(design),
        parameter_names = copy(design.parameter_names),
        parameter_values = copy(direct),
        blocks = _candidate_block_value_rows(design.blocks, design.parameter_names, direct),
        constraint_rows,
        rows,
        pointwise_loglikelihood = pointwise,
        loglikelihood,
        summary = (;
            flag = passed ? :ok : :pointwise_fixture_mismatch,
            passed,
            n_parameters = length(direct),
            n_observations = design.spec.data.n,
            n_categories = length(design.spec.data.category_levels),
            n_rows = length(rows),
            n_pointwise = length(pointwise),
            n_constraints = length(constraint_rows),
            n_failed_constraints,
            loglikelihood,
        ),
    )
end

function _mgmfrm_confirmatory_candidate_pointwise_fixture(
        spec::FacetSpec,
        direct_params::AbstractVector)
    return _mgmfrm_confirmatory_candidate_pointwise_fixture(
        getdesign(spec; preview = true),
        direct_params,
    )
end

function _mgmfrm_confirmatory_candidate_pointwise_fixture(
        target::_MGMFRMGuardedLocalFitLogDensity,
        raw_params::AbstractVector)
    _check_source_fixture_raw_vector(target, raw_params)
    raw = Float64.(collect(raw_params))
    direct = _mgmfrm_source_constrained_params_from_unconstrained(target.design, raw)
    direct_fixture = _mgmfrm_confirmatory_candidate_pointwise_fixture(target.design, direct)
    return merge(direct_fixture, (;
        _mgmfrm_ability_prior_metadata(target.prior)...,
        raw_parameter_names = copy(target.blueprint.parameter_names),
        raw_parameter_values = copy(raw),
        raw_blocks = _candidate_block_value_rows(
            target.blueprint.blocks,
            target.blueprint.parameter_names,
            raw,
        ),
    ))
end

function _mgmfrm_guarded_local_fit_direct_draw_values(
        target::_MGMFRMGuardedLocalFitLogDensity,
        raw_draws::AbstractMatrix{<:Real}; store_pointwise::Bool = true)
    # Rebuild once per call so changes to the owned design are rechecked.
    blueprint = _mgmfrm_source_unconstrained_blueprint(target.design)
    loading_indices = _mgmfrm_source_loading_index_matrix(target.design)
    n_draws = size(raw_draws, 1)
    n_direct = length(target.blueprint.constrained_parameter_names)
    n_observations = target.design.spec.data.n
    direct_draws = Matrix{Float64}(undef, n_draws, n_direct)
    pointwise = store_pointwise ? Matrix{Float64}(undef, n_draws, n_observations) : nothing
    n_nonfinite_pointwise = 0
    loglikelihood = Vector{Float64}(undef, n_draws)
    for draw in 1:n_draws
        raw = collect(@view raw_draws[draw, :])
        direct = _mgmfrm_source_constrained_params_from_unconstrained(target.design, raw, blueprint)
        direct_pointwise = _mgmfrm_source_pointwise_loglikelihood(target.design, direct, loading_indices)
        direct_draws[draw, :] .= direct
        if store_pointwise
            pointwise[draw, :] .= direct_pointwise
        else
            n_nonfinite_pointwise += count(!isfinite, direct_pointwise)
        end
        loglikelihood[draw] = sum(direct_pointwise; init = 0.0)
    end
    values = (;
        direct_draws,
        pointwise_loglikelihood = pointwise,
        loglikelihood,
    )
    return store_pointwise ? values : merge(values, (; n_nonfinite_pointwise))
end

function _mgmfrm_guarded_local_fit_direct_draw_constraint_rows(
        design::FacetDesign,
        direct_draws::AbstractMatrix{<:Real})
    n_draws = size(direct_draws, 1)
    n_draws == 0 && return NamedTuple[]
    template = _mgmfrm_direct_constraint_rows(design, @view direct_draws[1, :])
    values = [Float64[] for _ in template]
    n_failed = zeros(Int, length(template))
    for draw in 1:n_draws
        rows = _mgmfrm_direct_constraint_rows(design, @view direct_draws[draw, :])
        length(rows) == length(template) ||
            throw(ArgumentError("MGMFRM direct constraint row count changed across draws"))
        for index in eachindex(rows)
            rows[index].constraint === template[index].constraint &&
                rows[index].block === template[index].block ||
                throw(ArgumentError("MGMFRM direct constraint row identity changed across draws"))
            push!(values[index], Float64(rows[index].value))
            rows[index].passed || (n_failed[index] += 1)
        end
    end
    rows = NamedTuple[]
    for index in eachindex(template)
        row_values = values[index]
        target = Float64(template[index].target)
        push!(rows, (;
            constraint_index = index,
            constraint = template[index].constraint,
            block = template[index].block,
            target,
            tolerance = Float64(template[index].tolerance),
            n_draws,
            n_failed = n_failed[index],
            minimum_value = minimum(row_values),
            maximum_value = maximum(row_values),
            max_abs_target_error =
                maximum(abs(value - target) for value in row_values),
            passed = n_failed[index] == 0,
        ))
    end
    return rows
end

function _mgmfrm_initialization_status(initial_source::Symbol)
    initial_source === :default_zero_raw && return :default_zero_fallback
    initial_source === :user_supplied_raw && return :user_supplied_raw
    return :raw_initial_argument
end

function _mgmfrm_initialization_policy(
        target::_MGMFRMGuardedLocalFitLogDensity,
        initial::AbstractVector,
        initial_direct::AbstractVector,
        initial_logdensity::Real,
        controls::NamedTuple;
        initial_source::Symbol = :sampler_raw_initial_argument)
    init_jitter = Float64(_nt_get(controls, :init_jitter, 0.0))
    fallback_used = initial_source === :default_zero_raw
    return (;
        schema = "bayesianmgmfrm.mgmfrm_initialization_policy.v1",
        family = :mgmfrm,
        scope = :minimal_confirmatory_mgmfrm_candidate,
        target = :_mgmfrm_guarded_local_fit_logdensity,
        parameter_space = :raw_unconstrained,
        direct_parameter_space = :direct_constrained,
        initial_source,
        status = _mgmfrm_initialization_status(initial_source),
        fallback_used,
        fallback_policy = :zero_raw_vector_when_init_is_omitted,
        n_parameters = length(initial),
        n_direct_parameters = length(initial_direct),
        initial_raw_hash = _cache_hash(initial),
        initial_direct_hash = _cache_hash(initial_direct),
        zero_raw_initial = all(iszero, initial),
        finite_initial_raw_values = all(isfinite, initial),
        finite_initial_direct_values = all(isfinite, initial_direct),
        initial_logdensity = Float64(initial_logdensity),
        finite_initial_logdensity = isfinite(initial_logdensity),
        init_jitter,
        chain_initialization =
            init_jitter > 0 ?
            :raw_initial_plus_per_chain_jitter :
            :same_raw_initial_each_chain,
    )
end

function _mgmfrm_initialization_rows(policy::NamedTuple)
    return [
        (policy = :initial_raw_vector,
            check = :finite_raw_initial,
            parameter_space = :raw_unconstrained,
            status = policy.status,
            value = policy.initial_raw_hash,
            passed = policy.finite_initial_raw_values,
            fallback_used = policy.fallback_used,
            note = policy.fallback_policy),
        (policy = :initial_logdensity,
            check = :finite_initial_logdensity,
            parameter_space = :raw_unconstrained,
            status = policy.finite_initial_logdensity ? :finite : :nonfinite,
            value = policy.initial_logdensity,
            passed = policy.finite_initial_logdensity,
            fallback_used = policy.fallback_used,
            note = :initial_raw_vector_must_have_finite_target_density),
        (policy = :initial_direct_transform,
            check = :finite_direct_initial,
            parameter_space = :direct_constrained,
            status = policy.finite_initial_direct_values ? :finite : :nonfinite,
            value = policy.initial_direct_hash,
            passed = policy.finite_initial_direct_values,
            fallback_used = policy.fallback_used,
            note = :raw_initial_transformed_through_fixed_q_direct_map),
        (policy = :per_chain_initialization,
            check = :init_jitter,
            parameter_space = :raw_unconstrained,
            status = policy.init_jitter > 0 ? :jittered : :not_jittered,
            value = policy.init_jitter,
            passed = true,
            fallback_used = policy.fallback_used,
            note = policy.chain_initialization),
    ]
end

function _mgmfrm_initialization_rows(policy)
    return NamedTuple[]
end

function _mgmfrm_surface_direct_constraint_rows(surface)
    surface isa NamedTuple || return NamedTuple[]
    hasproperty(surface, :direct_constraint_rows) || return NamedTuple[]
    return surface.direct_constraint_rows
end

function _mgmfrm_surface_summary_value(surface, field::Symbol, default)
    surface isa NamedTuple || return default
    hasproperty(surface, :summary) || return default
    return _nt_get(surface.summary, field, default)
end

function _mgmfrm_direct_constraint_failures(surface, constraint::Symbol)
    rows = _mgmfrm_surface_direct_constraint_rows(surface)
    isempty(rows) && return missing
    for row in rows
        _nt_get(row, :constraint, missing) === constraint || continue
        return _nt_get(row, :n_failed,
            _nt_get(row, :passed, false) === true ? 0 : 1)
    end
    return missing
end

function _mgmfrm_constraint_passed(n_failed)
    ismissing(n_failed) && return missing
    return n_failed == 0
end

function _mgmfrm_constraint_status(n_failed)
    ismissing(n_failed) && return :not_recorded
    return n_failed == 0 ? :passed : :failed
end

function _mgmfrm_fixed_q_invariance_rows(
        design::FacetDesign,
        surface = nothing;
        prior::Union{Nothing,_SourceFixturePrior} = nothing)
    ability = _mgmfrm_ability_prior_metadata(prior)
    q_matrix = design.spec.q_matrix
    n_active_loadings = q_matrix === nothing ? missing : count(identity, q_matrix)
    loading_failures = _mgmfrm_direct_constraint_failures(
        surface,
        :item_dimension_discrimination_positive,
    )
    direct_failures = _mgmfrm_surface_summary_value(
        surface,
        :n_failed_direct_constraints,
        missing,
    )
    return [
        (policy = :q_matrix,
            check = :fixed_confirmatory_mask,
            status = q_matrix === nothing ? :missing : :fixed,
            parameter_space = :design,
            value = q_matrix === nothing ? missing : _q_matrix_manifest(q_matrix),
            passed = q_matrix !== nothing,
            note = :no_exploratory_loading_search),
        (policy = :latent_correlation,
            check = :identity_latent_correlation,
            status = :fixed_identity,
            parameter_space = :latent_ability,
            value = :identity,
            passed = true,
            note = :free_latent_correlation_blocked_for_guarded_candidate),
        (policy = :ability_scale,
            check = prior === nothing ? :normal_by_dimension : ability.ability_scale,
            status = prior === nothing ? :not_recorded :
                prior.person_sd == 1.0 ? :fixed_standard_normal_by_dimension :
                :fixed_normal_by_dimension,
            parameter_space = :latent_ability,
            value = ability.ability_scale,
            prior = ability.ability_prior,
            passed = prior === nothing ? missing : true,
            note = :prior_scale_not_posterior_scale_or_identification_proof),
        (policy = :loading_sign,
            check = :positive_q_masked_loadings,
            status = :fixed_positive,
            parameter_space = :direct_constrained,
            value = n_active_loadings,
            passed = true,
            note = :interpreted_loadings_use_log_link),
        (policy = :interpreted_loading_values,
            check = :item_dimension_discrimination_positive,
            status = _mgmfrm_constraint_status(loading_failures),
            parameter_space = :direct_constrained,
            value = loading_failures,
            passed = _mgmfrm_constraint_passed(loading_failures),
            note = :checked_in_direct_constraint_rows),
        (policy = :direct_constraints,
            check = :direct_constraint_failures,
            status = _mgmfrm_constraint_status(direct_failures),
            parameter_space = :direct_constrained,
            value = direct_failures,
            passed = _mgmfrm_constraint_passed(direct_failures),
            note = :all_direct_constraints_must_pass_before_interpretation),
        (policy = :rotation,
            check = :rotation_or_posthoc_alignment,
            status = :not_applicable_fixed_q,
            parameter_space = :latent_ability,
            value = :blocked,
            passed = true,
            note = :fixed_q_identity_correlation_defines_candidate_gauge),
        (policy = :dimension_permutation,
            check = :dimension_label_stability,
            status = :anchored_by_fixed_q_dimension_labels,
            parameter_space = :design,
            value = Tuple(design.spec.dimension_labels),
            passed = true,
            note = :dimension_labels_follow_fixed_q_columns),
        (policy = :exploratory_loading,
            check = :free_loading_search,
            status = :blocked,
            parameter_space = :design,
            value = :estimated_or_free_q_matrix,
            passed = true,
            note = :outside_guarded_local_mgmfrm_scope),
    ]
end

function _generalized_candidate_summary_flag(n_sampler_warnings::Int,
        n_nonfinite_logdensity::Int,
        n_failed_direct_constraints::Int,
        n_nonfinite_direct_loglikelihood::Int,
        raw_metrics,
        direct_metrics)
    (n_failed_direct_constraints > 0 || n_nonfinite_direct_loglikelihood > 0) &&
        return :direct_transform_warning
    (n_sampler_warnings > 0 || n_nonfinite_logdensity > 0) &&
        return :sampler_warning
    metrics = (raw_metrics, direct_metrics)
    any(row -> row.n_insufficient_chains > 0, metrics) &&
        return :insufficient_chains
    any(row -> row.n_insufficient_draws > 0, metrics) &&
        return :insufficient_draws
    any(row -> row.n_nonfinite_parameters > 0 ||
            row.n_degenerate_parameters > 0 ||
            _mcmc_metric_warning(row), metrics) && return :mcmc_warning
    return :ok
end

const _GeneralizedCandidateLogDensity = Union{
    _GMFRMPromotionCandidateLogDensity,
    _MGMFRMGuardedLocalFitLogDensity,
}

const _GENERALIZED_DEFAULT_RETAINED_DRAWS_PER_CHAIN = 100
const _GENERALIZED_DEFAULT_WARMUP_PER_CHAIN = 100
const _GENERALIZED_DEFAULT_CHAINS = 2

function _run_generalized_candidate_advancedhmc(
        target,
        raw_initial::AbstractVector;
        ndraws::Int = _GENERALIZED_DEFAULT_RETAINED_DRAWS_PER_CHAIN,
        warmup::Int = _GENERALIZED_DEFAULT_WARMUP_PER_CHAIN,
        chains::Int = _GENERALIZED_DEFAULT_CHAINS,
        step_size::Real = 0.03,
        rng::AbstractRNG = Random.default_rng(),
        seed = nothing,
        target_accept::Real = 0.8,
        max_depth::Int = 10,
        max_energy_error::Real = 1000.0,
        metric::Symbol = :diagonal,
        ad_backend::Symbol = :ForwardDiff,
        init_jitter::Real = 0.0,
        split_chains::Bool = true,
        rhat_threshold::Real = 1.01,
        ess_threshold::Real = 400,
        progress::Union{Bool,SamplingProgress} = false,
        record_warmup::Bool = false,
        chain_execution::Symbol = :serial,
        max_parallel_chains::Int = chains,
        _sampling_observer = nothing,
        _initial_transform = identity)
    _sampling_observer === nothing || _sampling_observer isa Function ||
        throw(ArgumentError("_sampling_observer must be a function or nothing"))
    step_size = _check_fit_controls(ndraws, warmup, chains, step_size)
    target_accept, max_energy_error, init_jitter =
        _check_nuts_controls(target_accept, max_depth, max_energy_error, init_jitter)
    gradient_backend = _gradient_backend_kind(ad_backend)
    checked = _check_diagnostic_thresholds(rhat_threshold, ess_threshold)
    _check_source_fixture_raw_vector(target, raw_initial)

    nparams = LogDensityProblems.dimension(target)
    nparams >= 1 ||
        throw(ArgumentError("at least one parameter is required for AdvancedHMC diagnostics"))
    initialization_coordinates = Float64.(collect(raw_initial))
    initial = _initial_transform(initialization_coordinates)
    initial_logdensity = LogDensityProblems.logdensity(target, initial)
    isfinite(initial_logdensity) ||
        throw(ArgumentError("initial raw parameter vector has non-finite log density"))
    fit_rng, rng_control = _fit_rng(rng, seed)
    total_draws = ndraws * chains
    draws = Matrix{Float64}(undef, total_draws, nparams)
    logdensities = Vector{Float64}(undef, total_draws)
    chain_ids = Vector{Int}(undef, total_draws)
    iterations = Vector{Int}(undef, total_draws)
    chain_acceptance = Vector{Float64}(undef, chains)
    stats_by_chain = [NamedTuple[] for _ in 1:chains]
    warmup_by_chain = record_warmup ? [NamedTuple[] for _ in 1:chains] : nothing
    controls = (;
        ndraws,
        warmup,
        chains,
        step_size = Float64(step_size),
        target_accept = Float64(target_accept),
        max_depth,
        max_energy_error = Float64(max_energy_error),
        metric,
        ad_backend,
        gradient_backend,
        rng = rng_control,
        init_jitter = Float64(init_jitter),
    )

    schedule = _sampling_chain_schedule(fit_rng, chains, chain_execution, max_parallel_chains)
    controls = merge(controls, schedule.metadata,
        (; adaptation_plan=_advancedhmc_adaptation_plan(warmup, metric)))
    progress = _threaded_progress(progress, schedule.mode)
    observer_guard = ReentrantLock()
    _with_sampling_progress(progress, chains, warmup, ndraws) do
        _foreach_sampling_chain(schedule, chains, fit_rng) do chain, chain_rng, cancelled
            chain_target = schedule.mode === :threads ? deepcopy(target) : target
            _progress_chain!(progress, chain, warmup, ndraws)
            chain_raw_initial, chain_initial = _with_sampler_context(:advancedhmc, chain, :initialization) do
                raw_values = _advancedhmc_initial(
                    initialization_coordinates, chain_rng, Float64(init_jitter))
                values = _initial_transform(raw_values)
                chain_logdensity = LogDensityProblems.logdensity(chain_target, values)
                isfinite(chain_logdensity) ||
                    throw(ArgumentError("chain $chain initial raw parameter vector has non-finite log density"))
                (raw_values, values)
            end
            gradient_target = _with_sampler_context(:advancedhmc, chain, :initialization) do
                _logdensity_gradient_target(chain_target, chain_initial, ad_backend).target
            end
            metric_object = _advancedhmc_metric(metric, nparams)
            hamiltonian = AdvancedHMC.Hamiltonian(
                metric_object,
                x -> LogDensityProblems.logdensity(gradient_target, x),
                x -> LogDensityProblems.logdensity_and_gradient(gradient_target, x),
            )
            integrator = AdvancedHMC.Leapfrog(Float64(step_size))
            kernel = AdvancedHMC.HMCKernel(
                AdvancedHMC.Trajectory{AdvancedHMC.MultinomialTS}(
                    integrator,
                    AdvancedHMC.GeneralisedNoUTurn(
                        max_depth,
                        Float64(max_energy_error),
                    ),
                ),
            )
            adaptor = _advancedhmc_adaptor(metric_object, integrator, target_accept, warmup)
            samples, stats = _with_sampler_context(:advancedhmc, chain, :sampling) do
                # Private observation hook: reuse AdvancedHMC's iteration notification,
                # preserving its sampler/adaptation loop and the saved run schema.
                observer = _sampling_chain_observer(_sampling_observer, cancelled, observer_guard)
                options = _advancedhmc_progress_options(progress, chain, warmup, ndraws, observer)
                observer === nothing || observer((; phase = :sampling_start, chain,
                    initial_raw = copy(chain_raw_initial), initial_sampling = copy(chain_initial),
                    metric = deepcopy(metric_object), controls))
                result = AdvancedHMC.sample(
                    chain_rng,
                    hamiltonian,
                    kernel,
                    chain_initial,
                    warmup + ndraws,
                    adaptor,
                    warmup;
                    drop_warmup = warmup > 0 && !record_warmup,
                    verbose = false,
                    options...,
                )
                observer === nothing || observer((; phase = :sampling_end, chain))
                result
            end
            _with_sampler_context(:advancedhmc, chain, :output_validation) do
                offset = record_warmup ? warmup : 0
                expected = ndraws + offset
                length(samples) == expected ||
                    throw(ArgumentError("chain $chain: AdvancedHMC returned $(length(samples)) draw(s); expected $expected"))
                length(stats) == expected ||
                    throw(ArgumentError("chain $chain: AdvancedHMC returned $(length(stats)) sampler-stat row(s); expected $expected"))
                for iteration in 1:offset
                    push!(warmup_by_chain[chain], _warmup_stat_row(stats[iteration], chain, iteration))
                end
                chain_stats = stats_by_chain[chain]
                for iteration in 1:ndraws
                    row = (chain - 1) * ndraws + iteration
                    stat_row = _advancedhmc_stat_row(stats[offset + iteration], chain, iteration)
                    _store_sampler_draw!(draws, logdensities, samples[offset + iteration], stat_row, row)
                    chain_ids[row] = chain
                    iterations[row] = iteration
                    push!(chain_stats, stat_row)
                end
                chain_acceptance[chain] = _stat_mean(chain_stats, :acceptance_rate)
            end
        end
    end

    sampler_stats = reduce(vcat, stats_by_chain)
    warmup_stats = record_warmup ? reduce(vcat, warmup_by_chain) : nothing

    sampler_rows = _generalized_candidate_sampler_rows(
        logdensities,
        iterations,
        chain_acceptance,
        sampler_stats,
        controls,
        :advancedhmc,
    )

    run = (;
        checked,
        nparams,
        initial,
        initial_logdensity,
        total_draws,
        draws,
        logdensities,
        chain_ids,
        iterations,
        chain_acceptance,
        sampler_stats,
        controls,
        sampler_rows,
        backend = :advancedhmc,
        sampler = :nuts,
        split_chains_requested = split_chains,
        actual_split = split_chains && chains >= 2 && ndraws >= 4,
    )
    return record_warmup ? merge(run, (; warmup_stats)) : run
end

_generalized_candidate_direct_draw_values(
        target::_GMFRMPromotionCandidateLogDensity,
        draws::AbstractMatrix{<:Real}) =
    _gmfrm_candidate_direct_draw_values(target, draws)

_generalized_candidate_direct_draw_values(
        target::_MGMFRMGuardedLocalFitLogDensity,
        draws::AbstractMatrix{<:Real}) =
    _mgmfrm_guarded_local_fit_direct_draw_values(target, draws)

_generalized_candidate_direct_draw_constraint_rows(
        target::_GMFRMPromotionCandidateLogDensity,
        direct_draws::AbstractMatrix{<:Real}) =
    _gmfrm_candidate_direct_draw_constraint_rows(target.design, direct_draws)

_generalized_candidate_direct_draw_constraint_rows(
        target::_MGMFRMGuardedLocalFitLogDensity,
        direct_draws::AbstractMatrix{<:Real}) =
    _mgmfrm_guarded_local_fit_direct_draw_constraint_rows(
        target.design,
        direct_draws,
    )

function _generalized_candidate_diagnostic_tables(
        target::_GeneralizedCandidateLogDensity,
        run::NamedTuple)
    return _generalized_candidate_diagnostic_tables(target, run, target.blueprint)
end

# The caller supplies the complete coordinate layout, including any extra
# population parameters. Reconstruction remains target-specific.
function _generalized_candidate_diagnostic_tables(target, run::NamedTuple, blueprint;
        direct_values = nothing)
    checked = run.checked
    chains = run.controls.chains
    ndraws = run.controls.ndraws
    split_chains = run.split_chains_requested
    parameter_rows = _candidate_mcmc_diagnostic_rows(
        run.draws,
        blueprint.parameter_names,
        chains;
        parameter_space = :raw_unconstrained,
        split_chains,
        rhat_threshold = checked.rhat_threshold,
        ess_threshold = checked.ess_threshold,
    )
    block_rows = _candidate_parameter_block_diagnostics(
        blueprint.blocks,
        blueprint.parameter_names,
        parameter_rows;
        parameter_space = :raw_unconstrained,
        chains,
        draws_per_chain = ndraws,
        total_draws = run.total_draws,
        split_chains = run.actual_split,
        split_chains_requested = split_chains,
        rhat_threshold = checked.rhat_threshold,
        ess_threshold = checked.ess_threshold,
    )
    direct_values === nothing && (direct_values = _generalized_candidate_direct_draw_values(
        target,
        run.draws,
    ))
    direct_constraint_rows =
        _generalized_candidate_direct_draw_constraint_rows(
            target,
            direct_values.direct_draws,
        )
    direct_parameter_rows = _candidate_mcmc_diagnostic_rows(
        direct_values.direct_draws,
        blueprint.constrained_parameter_names,
        chains;
        parameter_space = :direct_constrained,
        structurally_fixed_parameters =
            _structurally_fixed_constrained_parameter_names(blueprint),
        split_chains,
        rhat_threshold = checked.rhat_threshold,
        ess_threshold = checked.ess_threshold,
    )
    direct_block_rows = _candidate_parameter_block_diagnostics(
        blueprint.constrained_blocks,
        blueprint.constrained_parameter_names,
        direct_parameter_rows;
        parameter_space = :direct_constrained,
        chains,
        draws_per_chain = ndraws,
        total_draws = run.total_draws,
        split_chains = run.actual_split,
        split_chains_requested = split_chains,
        rhat_threshold = checked.rhat_threshold,
        ess_threshold = checked.ess_threshold,
    )

    warning_flags = (
        :insufficient_chains,
        :insufficient_draws,
        :nonfinite_draws,
        :degenerate_draws,
        :mcmc_warning,
    )
    n_sampler_warnings = count(row -> row.flag !== :ok, run.sampler_rows)
    n_block_warnings = count(row -> row.flag in warning_flags, block_rows)
    n_direct_block_warnings =
        count(row -> row.flag in warning_flags, direct_block_rows)
    n_nonfinite_logdensity =
        sum(row.n_nonfinite_logdensity for row in run.sampler_rows)
    n_nonfinite_direct_loglikelihood =
        count(!isfinite, direct_values.loglikelihood) +
        (direct_values.pointwise_loglikelihood === nothing ?
            direct_values.n_nonfinite_pointwise :
            count(!isfinite, direct_values.pointwise_loglikelihood))
    n_failed_direct_constraints =
        sum(row.n_failed for row in direct_constraint_rows)
    n_divergences =
        _sum_nonmissing(row.n_divergences for row in run.sampler_rows)
    n_max_treedepth =
        _sum_nonmissing(row.n_max_treedepth for row in run.sampler_rows)
    e_bfmi_coverage = _ebfmi_coverage(run.sampler_rows)
    raw_metrics = _mcmc_metric_summary(
        parameter_rows,
        checked.rhat_threshold,
        checked.ess_threshold,
    )
    direct_metrics = _mcmc_metric_summary(
        direct_parameter_rows,
        checked.rhat_threshold,
        checked.ess_threshold,
    )
    combined_metrics = _mcmc_metric_summary(
        vcat(parameter_rows, direct_parameter_rows),
        checked.rhat_threshold,
        checked.ess_threshold,
    )
    metric_fields = _generalized_mcmc_metric_fields(
        raw_metrics,
        direct_metrics,
        combined_metrics,
    )
    flag = _generalized_candidate_summary_flag(
        n_sampler_warnings,
        n_nonfinite_logdensity,
        n_failed_direct_constraints,
        n_nonfinite_direct_loglikelihood,
        raw_metrics,
        direct_metrics,
    )
    return (;
        direct_values,
        direct_constraint_rows,
        parameter_rows,
        block_rows,
        direct_parameter_rows,
        direct_block_rows,
        raw_metrics,
        direct_metrics,
        combined_metrics,
        metric_fields,
        flag,
        n_sampler_warnings,
        n_block_warnings,
        n_direct_block_warnings,
        n_nonfinite_logdensity,
        n_nonfinite_direct_loglikelihood,
        n_failed_direct_constraints,
        n_divergences,
        n_max_treedepth,
        e_bfmi_coverage,
    )
end

function _gmfrm_promotion_candidate_sampler_diagnostics(
        target::_GMFRMPromotionCandidateLogDensity,
        raw_initial::AbstractVector = initial_params(target);
        ndraws::Int = _GENERALIZED_DEFAULT_RETAINED_DRAWS_PER_CHAIN,
        warmup::Int = _GENERALIZED_DEFAULT_WARMUP_PER_CHAIN,
        chains::Int = _GENERALIZED_DEFAULT_CHAINS,
        step_size::Real = 0.03,
        rng::AbstractRNG = Random.default_rng(),
        seed = nothing,
        target_accept::Real = 0.8,
        max_depth::Int = 10,
        max_energy_error::Real = 1000.0,
        metric::Symbol = :diagonal,
        ad_backend::Symbol = :ForwardDiff,
        init_jitter::Real = 0.0,
        split_chains::Bool = true,
        rhat_threshold::Real = 1.01,
        ess_threshold::Real = 400,
        chain_execution::Symbol = :serial,
        max_parallel_chains::Int = chains,
        record_warmup::Bool = false,
        progress::Union{Bool,SamplingProgress} = false)
    run = _run_generalized_candidate_advancedhmc(
        target,
        raw_initial;
        ndraws,
        warmup,
        chains,
        step_size,
        rng,
        seed,
        target_accept,
        max_depth,
        max_energy_error,
        metric,
        ad_backend,
        init_jitter,
        split_chains,
        rhat_threshold,
        ess_threshold,
        chain_execution, max_parallel_chains,
        record_warmup,
        progress,
    )
    return _gmfrm_promotion_candidate_diagnostic_surface(target, run)
end

function _gmfrm_promotion_candidate_diagnostic_surface(
        target::_GMFRMPromotionCandidateLogDensity,
        run::NamedTuple)
    checked = run.checked
    chains = run.controls.chains
    ndraws = run.controls.ndraws
    split_chains = run.split_chains_requested
    nparams = run.nparams
    initial = run.initial
    initial_logdensity = run.initial_logdensity
    total_draws = run.total_draws
    draws = run.draws
    logdensities = run.logdensities
    chain_ids = run.chain_ids
    iterations = run.iterations
    chain_acceptance = run.chain_acceptance
    sampler_stats = run.sampler_stats
    controls = _with_warmup_diagnostics(
        run.controls, get(run, :warmup_stats, nothing), run.backend)
    sampler_rows = run.sampler_rows
    actual_split = run.actual_split
    diagnostic_tables = _generalized_candidate_diagnostic_tables(target, run)
    direct_values = diagnostic_tables.direct_values
    direct_constraint_rows = diagnostic_tables.direct_constraint_rows
    parameter_rows = diagnostic_tables.parameter_rows
    block_rows = diagnostic_tables.block_rows
    direct_parameter_rows = diagnostic_tables.direct_parameter_rows
    direct_block_rows = diagnostic_tables.direct_block_rows
    raw_metrics = diagnostic_tables.raw_metrics
    direct_metrics = diagnostic_tables.direct_metrics
    combined_metrics = diagnostic_tables.combined_metrics
    metric_fields = diagnostic_tables.metric_fields
    flag = diagnostic_tables.flag
    n_sampler_warnings = diagnostic_tables.n_sampler_warnings
    n_block_warnings = diagnostic_tables.n_block_warnings
    n_direct_block_warnings = diagnostic_tables.n_direct_block_warnings
    n_nonfinite_logdensity = diagnostic_tables.n_nonfinite_logdensity
    n_nonfinite_direct_loglikelihood =
        diagnostic_tables.n_nonfinite_direct_loglikelihood
    n_failed_direct_constraints =
        diagnostic_tables.n_failed_direct_constraints
    n_divergences = diagnostic_tables.n_divergences
    n_max_treedepth = diagnostic_tables.n_max_treedepth
    e_bfmi_coverage = diagnostic_tables.e_bfmi_coverage
    initial_direct = _gmfrm_source_constrained_params_from_unconstrained(target.design, initial)

    return (;
        schema = "bayesianmgmfrm.gmfrm_promotion_candidate_sampler_diagnostics.v1",
        family = :gmfrm,
        scope = :scalar_gmfrm_source_aligned,
        status = :internal_promotion_candidate,
        public_fit = false,
        fit_ready = false,
        target = :_gmfrm_promotion_candidate_logdensity,
        density_space = :raw_unconstrained,
        parameter_layout = fit_ready_parameter_layout(target.design),
        backend = run.backend,
        sampler = run.sampler,
        raw_parameter_names = copy(target.blueprint.parameter_names),
        raw_blocks = _candidate_block_value_rows(
            target.blueprint.blocks,
            target.blueprint.parameter_names,
            initial,
        ),
        direct_parameter_names = copy(target.blueprint.constrained_parameter_names),
        direct_blocks = _candidate_block_value_rows(
            target.blueprint.constrained_blocks,
            target.blueprint.constrained_parameter_names,
            initial_direct,
        ),
        initial_raw_parameter_values = copy(initial),
        initial_direct_parameter_values = copy(initial_direct),
        initial_logdensity,
        draws,
        logdensity = logdensities,
        direct_draws = direct_values.direct_draws,
        direct_pointwise_loglikelihood = direct_values.pointwise_loglikelihood,
        direct_loglikelihood = direct_values.loglikelihood,
        chain_ids,
        iterations,
        chain_acceptance_rate = chain_acceptance,
        sampler_controls = controls,
        sampler_stats,
        sampler_rows,
        parameter_rows,
        block_rows,
        direct_constraint_rows,
        direct_parameter_rows,
        direct_block_rows,
        summary = (;
            diagnostic_contract = _MCMC_DIAGNOSTIC_CONTRACT,
            diagnostic_contract_details = _mcmc_diagnostic_contract_record(),
            flag,
            passed = flag === :ok,
            classical_compatibility_flag =
                _classical_compatibility_block_flag(
                    length(parameter_rows) + length(direct_parameter_rows),
                    combined_metrics,
                ),
            n_chains = chains,
            draws_per_chain = ndraws,
            total_draws,
            n_parameters = nparams,
            n_direct_parameters = size(direct_values.direct_draws, 2),
            n_diagnostic_parameters =
                nparams + size(direct_values.direct_draws, 2),
            n_quality_gate_parameters =
                combined_metrics.n_quality_gate_parameters,
            n_structurally_fixed_parameters =
                combined_metrics.n_structurally_fixed_parameters,
            split_chains = actual_split,
            split_chains_requested = split_chains,
            rhat_threshold = checked.rhat_threshold,
            ess_threshold = checked.ess_threshold,
            metric_fields...,
            n_block_warnings,
            n_direct_block_warnings,
            n_sampler_warnings,
            n_nonfinite_logdensity,
            n_nonfinite_direct_loglikelihood,
            n_direct_constraints = length(direct_constraint_rows),
            n_failed_direct_constraints,
            n_divergences,
            n_max_treedepth,
            e_bfmi_coverage...,
        ),
    )
end

function _gmfrm_promotion_candidate_sampler_diagnostics(
        design::FacetDesign,
        raw_initial::AbstractVector = initial_params(_gmfrm_promotion_candidate_logdensity(design));
        prior::_SourceFixturePrior = _SourceFixturePrior(),
        kwargs...)
    target = _gmfrm_promotion_candidate_logdensity(design; prior)
    return _gmfrm_promotion_candidate_sampler_diagnostics(target, raw_initial; kwargs...)
end

function _gmfrm_promotion_candidate_sampler_diagnostics(
        spec::FacetSpec,
        raw_initial::AbstractVector = initial_params(_gmfrm_promotion_candidate_logdensity(spec));
        prior::_SourceFixturePrior = _SourceFixturePrior(),
        kwargs...)
    target = _gmfrm_promotion_candidate_logdensity(spec; prior)
    return _gmfrm_promotion_candidate_sampler_diagnostics(target, raw_initial; kwargs...)
end

function _mgmfrm_guarded_local_fit_sampler_diagnostics(
        target::_MGMFRMGuardedLocalFitLogDensity,
        raw_initial::AbstractVector = initial_params(target);
        ndraws::Int = _GENERALIZED_DEFAULT_RETAINED_DRAWS_PER_CHAIN,
        warmup::Int = _GENERALIZED_DEFAULT_WARMUP_PER_CHAIN,
        chains::Int = _GENERALIZED_DEFAULT_CHAINS,
        step_size::Real = 0.03,
        rng::AbstractRNG = Random.default_rng(),
        seed = nothing,
        target_accept::Real = 0.8,
        max_depth::Int = 10,
        max_energy_error::Real = 1000.0,
        metric::Symbol = :diagonal,
        ad_backend::Symbol = :ForwardDiff,
        init_jitter::Real = 0.0,
        split_chains::Bool = true,
        rhat_threshold::Real = 1.01,
        ess_threshold::Real = 400,
        chain_execution::Symbol = :serial,
        max_parallel_chains::Int = chains,
        record_warmup::Bool = false,
        progress::Union{Bool,SamplingProgress} = false,
        _sampling_observer = nothing,
        initial_source::Symbol = :sampler_raw_initial_argument)
    target.blueprint.family === :mgmfrm ||
        throw(ArgumentError("_mgmfrm_guarded_local_fit_sampler_diagnostics requires an MGMFRM guarded target"))
    # Validate once at entry and rebuild mutable numerical views before sampling.
    target = _mgmfrm_guarded_local_fit_logdensity(target.design; prior = target.prior)
    run = _run_generalized_candidate_advancedhmc(
        target,
        raw_initial;
        ndraws,
        warmup,
        chains,
        step_size,
        rng,
        seed,
        target_accept,
        max_depth,
        max_energy_error,
        metric,
        ad_backend,
        init_jitter,
        split_chains,
        rhat_threshold,
        ess_threshold,
        chain_execution, max_parallel_chains,
        record_warmup,
        progress,
        _sampling_observer,
    )
    return _mgmfrm_guarded_local_fit_diagnostic_surface(
        target,
        run;
        initial_source,
    )
end

function _mgmfrm_guarded_local_fit_diagnostic_surface(
        target::_MGMFRMGuardedLocalFitLogDensity,
        run::NamedTuple;
        initial_source::Symbol = :sampler_raw_initial_argument)
    checked = run.checked
    chains = run.controls.chains
    ndraws = run.controls.ndraws
    split_chains = run.split_chains_requested
    nparams = run.nparams
    initial = run.initial
    initial_logdensity = run.initial_logdensity
    total_draws = run.total_draws
    draws = run.draws
    logdensities = run.logdensities
    chain_ids = run.chain_ids
    iterations = run.iterations
    chain_acceptance = run.chain_acceptance
    sampler_stats = run.sampler_stats
    controls = _with_warmup_diagnostics(
        run.controls, get(run, :warmup_stats, nothing), run.backend)
    sampler_rows = run.sampler_rows
    actual_split = run.actual_split
    diagnostic_tables = _generalized_candidate_diagnostic_tables(target, run)
    direct_values = diagnostic_tables.direct_values
    direct_constraint_rows = diagnostic_tables.direct_constraint_rows
    parameter_rows = diagnostic_tables.parameter_rows
    block_rows = diagnostic_tables.block_rows
    direct_parameter_rows = diagnostic_tables.direct_parameter_rows
    direct_block_rows = diagnostic_tables.direct_block_rows
    raw_metrics = diagnostic_tables.raw_metrics
    direct_metrics = diagnostic_tables.direct_metrics
    combined_metrics = diagnostic_tables.combined_metrics
    metric_fields = diagnostic_tables.metric_fields
    flag = diagnostic_tables.flag
    n_sampler_warnings = diagnostic_tables.n_sampler_warnings
    n_block_warnings = diagnostic_tables.n_block_warnings
    n_direct_block_warnings = diagnostic_tables.n_direct_block_warnings
    n_nonfinite_logdensity = diagnostic_tables.n_nonfinite_logdensity
    n_nonfinite_direct_loglikelihood =
        diagnostic_tables.n_nonfinite_direct_loglikelihood
    n_failed_direct_constraints =
        diagnostic_tables.n_failed_direct_constraints
    n_divergences = diagnostic_tables.n_divergences
    n_max_treedepth = diagnostic_tables.n_max_treedepth
    e_bfmi_coverage = diagnostic_tables.e_bfmi_coverage
    initial_direct = _mgmfrm_source_constrained_params_from_unconstrained(
        target.design,
        initial,
    )
    initialization_policy = _mgmfrm_initialization_policy(
        target,
        initial,
        initial_direct,
        initial_logdensity,
        controls;
        initial_source,
    )
    fixed_q_invariance_rows = _mgmfrm_fixed_q_invariance_rows(
        target.design,
        (; direct_constraint_rows, summary = (; n_failed_direct_constraints));
        prior = target.prior,
    )

    return (;
        schema = "bayesianmgmfrm.mgmfrm_guarded_local_fit_sampler_diagnostics.v1",
        family = :mgmfrm,
        scope = :minimal_confirmatory_mgmfrm_candidate,
        status = :guarded_local_fit,
        public_fit = true,
        experimental_public = true,
        fit_ready = true,
        target = :_mgmfrm_guarded_local_fit_logdensity,
        density_space = :raw_unconstrained,
        parameter_layout = fit_ready_parameter_layout(target.design),
        backend = run.backend,
        sampler = run.sampler,
        raw_parameter_names = copy(target.blueprint.parameter_names),
        raw_blocks = _candidate_block_value_rows(
            target.blueprint.blocks,
            target.blueprint.parameter_names,
            initial,
        ),
        direct_parameter_names = copy(target.blueprint.constrained_parameter_names),
        direct_blocks = _candidate_block_value_rows(
            target.blueprint.constrained_blocks,
            target.blueprint.constrained_parameter_names,
            initial_direct,
        ),
        initialization_policy,
        initialization_rows = _mgmfrm_initialization_rows(initialization_policy),
        fixed_q_invariance_rows,
        initial_raw_parameter_values = copy(initial),
        initial_direct_parameter_values = copy(initial_direct),
        initial_logdensity,
        draws,
        logdensity = logdensities,
        direct_draws = direct_values.direct_draws,
        direct_pointwise_loglikelihood = direct_values.pointwise_loglikelihood,
        direct_loglikelihood = direct_values.loglikelihood,
        chain_ids,
        iterations,
        chain_acceptance_rate = chain_acceptance,
        sampler_controls = controls,
        sampler_stats,
        sampler_rows,
        parameter_rows,
        block_rows,
        direct_constraint_rows,
        direct_parameter_rows,
        direct_block_rows,
        summary = (;
            diagnostic_contract = _MCMC_DIAGNOSTIC_CONTRACT,
            diagnostic_contract_details = _mcmc_diagnostic_contract_record(),
            flag,
            passed = flag === :ok,
            classical_compatibility_flag =
                _classical_compatibility_block_flag(
                    length(parameter_rows) + length(direct_parameter_rows),
                    combined_metrics,
                ),
            n_chains = chains,
            draws_per_chain = ndraws,
            total_draws,
            n_parameters = nparams,
            n_direct_parameters = size(direct_values.direct_draws, 2),
            n_diagnostic_parameters =
                nparams + size(direct_values.direct_draws, 2),
            n_quality_gate_parameters =
                combined_metrics.n_quality_gate_parameters,
            n_structurally_fixed_parameters =
                combined_metrics.n_structurally_fixed_parameters,
            split_chains = actual_split,
            split_chains_requested = split_chains,
            rhat_threshold = checked.rhat_threshold,
            ess_threshold = checked.ess_threshold,
            metric_fields...,
            n_block_warnings,
            n_direct_block_warnings,
            n_sampler_warnings,
            n_nonfinite_logdensity,
            n_nonfinite_direct_loglikelihood,
            n_direct_constraints = length(direct_constraint_rows),
            n_failed_direct_constraints,
            n_divergences,
            n_max_treedepth,
            e_bfmi_coverage...,
        ),
    )
end

function _mgmfrm_guarded_local_fit_sampler_diagnostics(
        design::FacetDesign,
        raw_initial::AbstractVector = initial_params(_mgmfrm_guarded_local_fit_logdensity(design));
        prior::_SourceFixturePrior = _SourceFixturePrior(),
        kwargs...)
    target = _mgmfrm_guarded_local_fit_logdensity(design; prior)
    return _mgmfrm_guarded_local_fit_sampler_diagnostics(target, raw_initial; kwargs...)
end

function _mgmfrm_guarded_local_fit_sampler_diagnostics(
        spec::FacetSpec,
        raw_initial::AbstractVector = initial_params(_mgmfrm_guarded_local_fit_logdensity(spec));
        prior::_SourceFixturePrior = _SourceFixturePrior(),
        kwargs...)
    target = _mgmfrm_guarded_local_fit_logdensity(spec; prior)
    return _mgmfrm_guarded_local_fit_sampler_diagnostics(target, raw_initial; kwargs...)
end

function _experimental_gmfrm_prior(prior)
    prior === nothing && return _SourceFixturePrior()
    prior isa _SourceFixturePrior && return prior
    prior isa GeneralizedPrior && return _source_fixture_prior(prior)
    throw(_guarded_gmfrm_unsupported_error(
        :prior,
        Symbol(nameof(typeof(prior))),
        :scalar_gmfrm_prior_likelihood_sensitivity_grid,
        "The scalar GMFRM fit accepts only " *
        "BayesianMGMFRM.Experimental.GeneralizedPrior, which defines scales " *
        "on raw unconstrained coordinates. Omit `prior` to use its default.",
    ))
end

function _guarded_gmfrm_unsupported_error(
        option::Symbol,
        value,
        next_gate::Symbol,
        reason::AbstractString)
    return _guarded_generalized_unsupported_error(
        "scalar GMFRM fit",
        :gmfrm,
        option,
        value,
        reason;
        next_gate,
    )
end

function _check_experimental_gmfrm_spec(spec::FacetSpec)
    _check_guarded_generalized_spec(
        spec,
        "scalar GMFRM fit",
    )
    return nothing
end

function _experimental_gmfrm_initial(target::_GMFRMPromotionCandidateLogDensity, init)
    init === nothing && return initial_params(target)
    length(init) == LogDensityProblems.dimension(target) ||
        throw(ArgumentError("init has length $(length(init)); expected $(LogDensityProblems.dimension(target))"))
    out = Float64.(collect(init))
    all(isfinite, out) || throw(ArgumentError("init contains non-finite values"))
    return out
end

function _gmfrm_fit_from_sampler_diagnostics(
        design::FacetDesign,
        prior::_SourceFixturePrior,
        diagnostic_surface)
    step = _stat_mean(diagnostic_surface.sampler_stats, :step_size)
    isfinite(step) || (step = Float64(diagnostic_surface.sampler_controls.step_size))
    return GMFRMFit(
        design,
        prior,
        Matrix{Float64}(diagnostic_surface.draws),
        Vector{Float64}(diagnostic_surface.logdensity),
        Matrix{Float64}(diagnostic_surface.direct_draws),
        Vector{Float64}(diagnostic_surface.direct_loglikelihood),
        Matrix{Float64}(diagnostic_surface.direct_pointwise_loglikelihood),
        Vector{Int}(diagnostic_surface.chain_ids),
        Vector{Int}(diagnostic_surface.iterations),
        Vector{Float64}(diagnostic_surface.chain_acceptance_rate),
        diagnostic_surface.backend,
        diagnostic_surface.sampler,
        Int(diagnostic_surface.sampler_controls.warmup),
        step,
        Vector{NamedTuple}(diagnostic_surface.sampler_stats),
        diagnostic_surface.sampler_controls,
        diagnostic_surface,
    )
end

function _fit_experimental_gmfrm(spec::FacetSpec;
        prior = nothing,
        backend::Symbol = :advancedhmc,
        init = nothing,
        kwargs...)
    _check_experimental_gmfrm_spec(spec)
    backend in (:advancedhmc, :cmdstan) ||
        throw(_guarded_gmfrm_unsupported_error(
            :backend,
            backend,
            :advancedhmc_guarded_sampler_policy,
            "guarded scalar GMFRM fitting supports backend = :advancedhmc " *
            "or :cmdstan",
        ))
    gmfrm_prior = _experimental_gmfrm_prior(prior)
    design = getdesign(spec; preview = true)
    target = _gmfrm_promotion_candidate_logdensity(design; prior = gmfrm_prior)
    raw_initial = _experimental_gmfrm_initial(target, init)
    diagnostic_surface = if backend === :advancedhmc
        _gmfrm_promotion_candidate_sampler_diagnostics(
            target,
            raw_initial;
            record_warmup = true,
            kwargs...,
        )
    else
        _cmdstan_gmfrm_sampler_diagnostics(
            target,
            raw_initial;
            record_warmup = true,
            kwargs...,
        )
    end
    return _gmfrm_fit_from_sampler_diagnostics(
        target.design,
        gmfrm_prior,
        diagnostic_surface,
    )
end

function _guarded_mgmfrm_prior(prior)
    prior === nothing && return _SourceFixturePrior()
    prior isa _SourceFixturePrior && return prior
    prior isa GeneralizedPrior && return _source_fixture_prior(prior)
    throw(_guarded_generalized_unsupported_error(
        "MGMFRM fit",
        :mgmfrm,
        :prior,
        Symbol(nameof(typeof(prior))),
        "The MGMFRM fit accepts only " *
        "BayesianMGMFRM.Experimental.GeneralizedPrior, which defines scales " *
        "on raw unconstrained coordinates. Omit `prior` to use its default.";
        next_gate = :mgmfrm_raw_prior_contract,
    ))
end

function _check_guarded_mgmfrm_spec(spec::FacetSpec)
    _check_guarded_generalized_spec(
        spec,
        "MGMFRM fit",
    )
    return nothing
end

function _guarded_mgmfrm_initial(target::_MGMFRMGuardedLocalFitLogDensity, init)
    init === nothing && return initial_params(target)
    length(init) == LogDensityProblems.dimension(target) ||
        throw(ArgumentError("init has length $(length(init)); expected $(LogDensityProblems.dimension(target))"))
    out = Float64.(collect(init))
    all(isfinite, out) || throw(ArgumentError("init contains non-finite values"))
    return out
end

function _mgmfrm_fit_from_sampler_diagnostics(
        design::FacetDesign,
        prior::_SourceFixturePrior,
        diagnostic_surface)
    step = _stat_mean(diagnostic_surface.sampler_stats, :step_size)
    isfinite(step) || (step = Float64(diagnostic_surface.sampler_controls.step_size))
    return MGMFRMFit(
        design,
        prior,
        Matrix{Float64}(diagnostic_surface.draws),
        Vector{Float64}(diagnostic_surface.logdensity),
        Matrix{Float64}(diagnostic_surface.direct_draws),
        Vector{Float64}(diagnostic_surface.direct_loglikelihood),
        Matrix{Float64}(diagnostic_surface.direct_pointwise_loglikelihood),
        Vector{Int}(diagnostic_surface.chain_ids),
        Vector{Int}(diagnostic_surface.iterations),
        Vector{Float64}(diagnostic_surface.chain_acceptance_rate),
        diagnostic_surface.backend,
        diagnostic_surface.sampler,
        Int(diagnostic_surface.sampler_controls.warmup),
        step,
        Vector{NamedTuple}(diagnostic_surface.sampler_stats),
        diagnostic_surface.sampler_controls,
        diagnostic_surface,
    )
end

function _fit_guarded_mgmfrm(spec::FacetSpec;
        prior = nothing,
        backend::Symbol = :advancedhmc,
        init = nothing,
        sampling_coordinates::Symbol = :raw,
        kwargs...)
    _check_guarded_mgmfrm_spec(spec)
    _check_mgmfrm_sampling_coordinates(spec, sampling_coordinates, backend, true)
    sampling_coordinates === :orthogonal_person_mean_item_offset &&
        return _fit_mgmfrm_location(spec; prior, init, kwargs...)
    backend in (:advancedhmc, :cmdstan) ||
        throw(_guarded_generalized_unsupported_error(
            "MGMFRM fit",
            :mgmfrm,
            :backend,
            backend,
            "guarded MGMFRM fitting supports backend = :advancedhmc or :cmdstan";
            next_gate = :advancedhmc_guarded_sampler_policy,
        ))
    mgmfrm_prior = _guarded_mgmfrm_prior(prior)
    design = getdesign(spec; preview = true)
    target = _mgmfrm_guarded_local_fit_logdensity(design; prior = mgmfrm_prior)
    raw_initial = _guarded_mgmfrm_initial(target, init)
    initial_source = init === nothing ? :default_zero_raw : :user_supplied_raw
    diagnostic_surface = if backend === :advancedhmc
        _mgmfrm_guarded_local_fit_sampler_diagnostics(
            target,
            raw_initial;
            initial_source,
            record_warmup = true,
            kwargs...,
        )
    else
        _cmdstan_mgmfrm_sampler_diagnostics(
            target,
            raw_initial;
            initial_source,
            record_warmup = true,
            kwargs...,
        )
    end
    return _mgmfrm_fit_from_sampler_diagnostics(
        target.design,
        mgmfrm_prior,
        diagnostic_surface,
    )
end

function _fit_experimental_mgmfrm(spec::FacetSpec; kwargs...)
    return _fit_guarded_mgmfrm(spec; kwargs...)
end

function _fit_guarded_generalized(spec::FacetSpec;
        sampling_coordinates::Symbol = :raw, kwargs...)
    _check_sampling_progress(get(kwargs, :progress, false), get(kwargs, :backend, :advancedhmc))
    _check_mgmfrm_sampling_coordinates(spec, sampling_coordinates,
        get(kwargs, :backend, :advancedhmc), true)
    spec.family === :gmfrm && return _fit_experimental_gmfrm(spec; kwargs...)
    spec.family === :mgmfrm && return _fit_experimental_mgmfrm(spec; sampling_coordinates, kwargs...)
    throw(ArgumentError(
        "fitting currently supports only family = :gmfrm or :mgmfrm",
    ))
end

function fit(spec::FacetSpec; experimental::Bool = false, method::Union{Nothing,Symbol} = nothing, kwargs...)
    if !experimental && _is_scale_identified_prior(get(kwargs, :prior, nothing))
        return _fit_scale_identified_facet_spec(spec; method, kwargs...)
    end
    if method !== nothing && method !== :nuts
        experimental && throw(ArgumentError("experimental = true applies to Bayesian generalized models, not frequentist method = $(repr(method))"))
        any(k -> k in (:target_accept, :adapt_delta, :max_depth, :max_treedepth), keys(kwargs)) &&
            throw(ArgumentError("NUTS controls (`target_accept`/`adapt_delta`, `max_depth`/`max_treedepth`) do not apply to frequentist `method = $(repr(method))`"))
        return FrequentistMFRM.fit(spec; method, kwargs...)
    end
    _reject_mfrm_fixed_q_fit(spec, "fit")
    experimental && return _fit_guarded_generalized(spec; kwargs...)
    return fit(getdesign(spec); kwargs...)
end

function _fit_status_policy(fit::MFRMFit)
    return _status_policy_manifest(
        fit.design.spec.family,
        fit.design.spec.estimation_status;
        public_fit = true,
        experimental_public = false,
        fit_ready = true,
        claim_scope = :minimal_mfrm_rsm_pcm,
    )
end

function _fit_status_policy(fit::GMFRMFit)
    return _status_policy_manifest(
        :gmfrm,
        fit.design.spec.estimation_status;
        public_fit = true,
        experimental_public = true,
        fit_ready = true,
        claim_scope = :guarded_scalar_rater_consistency_only,
    )
end

function _fit_status_policy(fit::MGMFRMFit)
    return _status_policy_manifest(
        :mgmfrm,
        fit.design.spec.estimation_status;
        public_fit = true,
        experimental_public = true,
        fit_ready = true,
        claim_scope = :fixed_q_confirmatory_only,
    )
end

function _fit_model_surface_audit(fit; view::Symbol)
    view in (:full, :public) ||
        throw(ArgumentError("view must be :full or :public"))
    rows = _model_surface_audit(
        fit.design;
        status_policy = _fit_status_policy(fit),
    )
    return view === :public ? _public_model_surface_rows(
        rows,
        _public_model_availability(fit.design.spec),
    ) : rows
end

model_surface_audit(fit::MFRMFit; view::Symbol = :full) =
    _fit_model_surface_audit(fit; view)

model_surface_audit(fit::GMFRMFit; view::Symbol = :full) =
    _fit_model_surface_audit(fit; view)

model_surface_audit(fit::MGMFRMFit; view::Symbol = :full) =
    _fit_model_surface_audit(fit; view)

function model_surface_check(
        fit::Union{MFRMFit,GMFRMFit,MGMFRMFit};
        view::Symbol = :full)
    rows = model_surface_audit(fit; view)
    return view === :full ? _model_surface_check_rows(rows) : rows
end

"""
    fit_metadata(fit::MFRMFit; view = :full)

Return report-ready metadata for a fitted minimal MFRM object, including data
dimensions, model family, threshold structure, posterior draw dimensions,
backend, sampler, warmup, step size, sampler controls, and prior scales. This
metadata helper does not itself report chain-aware convergence diagnostics; use
`diagnostics`, `sampler_diagnostics`, and `mcmc_diagnostics` for sampler and
R-hat/ESS summaries.

The compatibility default `view = :full` preserves the complete fitting
record. Use `view = :public` for a reader-facing projection with an explicit
family and stability label and a compact set of portable reporting fields.
"""
function fit_metadata(fit::MFRMFit; view::Symbol = :full)
    view in (:full, :public) ||
        throw(ArgumentError("view must be :full or :public"))
    identity = design_identity(fit.design)
    data = fit.design.spec.data
    metadata = (;
        n_observations = data.n,
        n_persons = length(data.person_levels),
        n_raters = length(data.rater_levels),
        n_items = length(data.item_levels),
        n_categories = length(data.category_levels),
        category_levels = copy(data.category_levels),
        category_scale = _category_scale_contract(data),
        optional_facets = sort(collect(keys(data.optional)); by = string),
        family = fit.design.spec.family,
        dimensions = fit.design.spec.dimensions,
        dimension_labels = copy(fit.design.spec.dimension_labels),
        discrimination = fit.design.spec.discrimination,
        thresholds = fit.design.spec.thresholds,
        estimation_status = fit.design.spec.estimation_status,
        scope = :minimal_mfrm_rsm_pcm,
        public_fit = true,
        experimental_public = false,
        fit_ready = true,
        status_policy = _fit_status_policy(fit),
        n_parameters = length(fit.design.parameter_names),
        n_draws = size(fit.draws, 1),
        n_chains = length(fit.chain_acceptance_rate),
        draws_per_chain = _fit_draws_per_chain(fit),
        n_log_posterior = length(fit.log_posterior),
        backend = fit.backend,
        sampler = fit.sampler,
        warmup = fit.warmup,
        step_size = fit.step_size,
        acceptance_rate = fit.acceptance_rate,
        chain_acceptance_rate = copy(fit.chain_acceptance_rate),
        sampler_controls = fit.sampler_controls,
        n_sampler_stats = length(fit.sampler_stats),
        prior = (;
            person_sd = fit.prior.person_sd,
            rater_sd = fit.prior.rater_sd,
            item_sd = fit.prior.item_sd,
            step_sd = fit.prior.step_sd,
        ),
        data_signature = fit.design.spec.validation.data_signature,
        design_identity = identity,
    )
    return view === :full ? metadata :
        _public_reader_payload(
            merge(metadata, (estimation_status = :supported,));
            schema = "bayesianmgmfrm.fit_metadata_public.v1",
            family = :mfrm,
            stability = :stable,
        )
end

function fit_metadata(fit::GMFRMFit; view::Symbol = :full)
    view in (:full, :public) ||
        throw(ArgumentError("view must be :full or :public"))
    identity = design_identity(fit.design)
    data = fit.design.spec.data
    diagnostic = fit.diagnostic_surface
    metadata = (;
        n_observations = data.n,
        n_persons = length(data.person_levels),
        n_raters = length(data.rater_levels),
        n_items = length(data.item_levels),
        n_categories = length(data.category_levels),
        category_levels = copy(data.category_levels),
        category_scale = _category_scale_contract(data),
        optional_facets = sort(collect(keys(data.optional)); by = string),
        family = fit.design.spec.family,
        dimensions = fit.design.spec.dimensions,
        dimension_labels = copy(fit.design.spec.dimension_labels),
        discrimination = fit.design.spec.discrimination,
        thresholds = fit.design.spec.thresholds,
        estimation_status = fit.design.spec.estimation_status,
        scope = :scalar_gmfrm_fit_ready_candidate,
        public_fit = true,
        experimental_public = true,
        status_policy = _fit_status_policy(fit),
        density_space = :raw_unconstrained,
        n_parameters = size(fit.draws, 2),
        n_direct_parameters = size(fit.direct_draws, 2),
        raw_parameter_names = copy(diagnostic.raw_parameter_names),
        direct_parameter_names = copy(diagnostic.direct_parameter_names),
        n_draws = size(fit.draws, 1),
        n_chains = length(fit.chain_acceptance_rate),
        draws_per_chain = _fit_draws_per_chain(fit),
        n_log_posterior = length(fit.log_posterior),
        backend = fit.backend,
        sampler = fit.sampler,
        warmup = fit.warmup,
        step_size = fit.step_size,
        acceptance_rate = _column_mean(fit.chain_acceptance_rate),
        chain_acceptance_rate = copy(fit.chain_acceptance_rate),
        sampler_controls = fit.sampler_controls,
        n_sampler_stats = length(fit.sampler_stats),
        prior = (;
            person_sd = fit.prior.person_sd,
            rater_sd = fit.prior.rater_sd,
            item_sd = fit.prior.item_sd,
            log_discrimination_sd = fit.prior.log_discrimination_sd,
            log_consistency_sd = fit.prior.log_consistency_sd,
            step_sd = fit.prior.step_sd,
        ),
        data_signature = fit.design.spec.validation.data_signature,
        design_identity = identity,
    )
    return view === :full ? metadata :
        _public_reader_payload(
            merge(metadata, (estimation_status = :experimental,));
            schema = "bayesianmgmfrm.fit_metadata_public.v1",
            family = :gmfrm,
            stability = :experimental,
        )
end

function fit_metadata(fit::MGMFRMFit; view::Symbol = :full)
    view in (:full, :public) ||
        throw(ArgumentError("view must be :full or :public"))
    identity = design_identity(fit.design)
    data = fit.design.spec.data
    diagnostic = fit.diagnostic_surface
    metadata = (;
        n_observations = data.n,
        n_persons = length(data.person_levels),
        n_raters = length(data.rater_levels),
        n_items = length(data.item_levels),
        n_categories = length(data.category_levels),
        category_levels = copy(data.category_levels),
        category_scale = _category_scale_contract(data),
        optional_facets = sort(collect(keys(data.optional)); by = string),
        family = fit.design.spec.family,
        dimensions = fit.design.spec.dimensions,
        dimension_labels = copy(fit.design.spec.dimension_labels),
        discrimination = fit.design.spec.discrimination,
        thresholds = fit.design.spec.thresholds,
        estimation_status = fit.design.spec.estimation_status,
        scope = :minimal_confirmatory_mgmfrm_candidate,
        public_fit = true,
        experimental_public = true,
        fit_ready = true,
        guarded_local_fit = true,
        status_policy = _fit_status_policy(fit),
        density_space = :raw_unconstrained,
        n_parameters = size(fit.draws, 2),
        n_direct_parameters = size(fit.direct_draws, 2),
        raw_parameter_names = copy(diagnostic.raw_parameter_names),
        direct_parameter_names = copy(diagnostic.direct_parameter_names),
        n_draws = size(fit.draws, 1),
        n_chains = length(fit.chain_acceptance_rate),
        draws_per_chain = _fit_draws_per_chain(fit),
        n_log_posterior = length(fit.log_posterior),
        backend = fit.backend,
        sampler = fit.sampler,
        warmup = fit.warmup,
        step_size = fit.step_size,
        acceptance_rate = _column_mean(fit.chain_acceptance_rate),
        chain_acceptance_rate = copy(fit.chain_acceptance_rate),
        sampler_controls = fit.sampler_controls,
        n_sampler_stats = length(fit.sampler_stats),
        q_matrix = _q_matrix_manifest(fit.design.spec.q_matrix),
        latent_correlation = :identity_fixed,
        prior = (;
            person_sd = fit.prior.person_sd,
            rater_sd = fit.prior.rater_sd,
            item_sd = fit.prior.item_sd,
            log_discrimination_sd = fit.prior.log_discrimination_sd,
            log_consistency_sd = fit.prior.log_consistency_sd,
            step_sd = fit.prior.step_sd,
        ),
        data_signature = fit.design.spec.validation.data_signature,
        design_identity = identity,
    )
    return view === :full ? metadata :
        _public_reader_payload(
            merge(metadata, (estimation_status = :experimental,));
            schema = "bayesianmgmfrm.fit_metadata_public.v1",
            family = :mgmfrm,
            stability = :experimental,
        )
end
