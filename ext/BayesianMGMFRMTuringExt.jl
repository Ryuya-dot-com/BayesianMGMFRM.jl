module BayesianMGMFRMTuringExt

using BayesianMGMFRM, Random
import Turing, AdvancedHMC, LogDensityProblems
using BayesianMGMFRM: FacetDesign, MFRMPrior, MFRMLogDensity, MFRMFit,
    _check_nuts_controls, _advancedhmc_initial, _with_sampler_context,
    logposterior, _warmup_stat_row, _advancedhmc_stat_row, _store_sampler_draw!,
    _stat_mean, _column_mean, _with_warmup_diagnostics,
    _turing_metric_type, _turing_discard_initial, _check_turing_ad_backend

Turing.@model function _turing_mfrm_logdensity_model(target::MFRMLogDensity,
        nparams::Int)
    params ~ Turing.filldist(Turing.Flat(), nparams)
    Turing.@addlogprob! LogDensityProblems.logdensity(target, params)
    return params
end

function _turing_adtype(ad_backend::Symbol)
    _check_turing_ad_backend(ad_backend)
    return Turing.AutoForwardDiff()
end

function _turing_params(transition, nparams::Int)
    values = getproperty(transition, :params)[Turing.@varname(params)]
    length(values) == nparams ||
        throw(ArgumentError("Turing returned $(length(values)) parameter(s); expected $nparams"))
    return values
end

function fit_turing(design::FacetDesign,
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
        progress::Bool,
        record_warmup::Bool = false)
    target_accept, max_energy_error, init_jitter =
        _check_nuts_controls(target_accept, max_depth, max_energy_error, init_jitter)

    nparams = length(design.parameter_names)
    nparams >= 1 || throw(ArgumentError("at least one parameter is required for Turing fitting"))
    adtype = _turing_adtype(ad_backend)
    metric_type = _turing_metric_type(metric)
    total_draws = ndraws * chains
    draws = Matrix{Float64}(undef, total_draws, nparams)
    logps = Vector{Float64}(undef, total_draws)
    chain_ids = Vector{Int}(undef, total_draws)
    iterations = Vector{Int}(undef, total_draws)
    chain_acceptance = Vector{Float64}(undef, chains)
    sampler_stats = NamedTuple[]
    warmup_stats = record_warmup ? NamedTuple[] : nothing
    offset = record_warmup ? warmup : 0
    target = MFRMLogDensity(design; prior)
    model = _turing_mfrm_logdensity_model(target, nparams)
    sampler = Turing.NUTS(warmup, Float64(target_accept), max_depth,
        Float64(max_energy_error), step, metric_type; adtype)
    discard_initial = _turing_discard_initial(warmup)
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
        gradient_backend = :ad,
        rng = rng_control,
        init_jitter = Float64(init_jitter),
        turing_model = :mfrm_logdensity_flat_parameter_model,
        chain_type = :raw_transitions,
        nadapts = warmup,
        discard_initial,
    )

    for chain in 1:chains
        chain_initial = _with_sampler_context(:turing, chain, :initialization) do
            values = _advancedhmc_initial(initial, rng, Float64(init_jitter))
            current_lp = logposterior(design, values, prior)
            isfinite(current_lp) || throw(ArgumentError("initial parameter vector has non-finite log posterior"))
            values
        end
        transitions = _with_sampler_context(:turing, chain, :sampling) do
            Turing.sample(
                rng,
                model,
                sampler,
                ndraws + offset;
                num_warmup = warmup,
                discard_initial = discard_initial - offset,
                progress,
                verbose = false,
                initial_params = Turing.InitFromParams((params = copy(chain_initial),)),
                chain_type = Any,
            )
        end
        _with_sampler_context(:turing, chain, :output_validation) do
            expected = ndraws + offset
            length(transitions) == expected ||
                throw(ArgumentError("Turing returned $(length(transitions)) draw(s); expected $expected"))
            # Turing omits is_adapt from its statistics. NUTS(warmup, ...) makes
            # these first transitions adapting; the initial state was discarded.
            # ponytail: buffer warmup transitions per chain; stream them if memory becomes a measured limit.
            for iteration in 1:offset
                push!(warmup_stats, _warmup_stat_row(
                    merge(transitions[iteration].stats, (; is_adapt = true)), chain, iteration))
            end
            chain_stats = NamedTuple[]
            for iteration in 1:ndraws
                row = (chain - 1) * ndraws + iteration
                values = _turing_params(transitions[offset + iteration], nparams)
                stat_row = _advancedhmc_stat_row(transitions[offset + iteration].stats, chain, iteration)
                _store_sampler_draw!(draws, logps, values, stat_row, row)
                chain_ids[row] = chain
                iterations[row] = iteration
                push!(chain_stats, stat_row)
                push!(sampler_stats, stat_row)
            end
            chain_acceptance[chain] = _stat_mean(chain_stats, :acceptance_rate)
        end
    end

    return MFRMFit(design, prior, draws, logps, _column_mean(chain_acceptance),
        chain_ids, iterations, chain_acceptance, :turing, :nuts, warmup,
        _stat_mean(sampler_stats, :step_size), sampler_stats,
        _with_warmup_diagnostics(controls, warmup_stats, :turing))
end

end
