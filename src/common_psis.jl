"""
    psis_loo(loglik; chain_ids=nothing, r_eff=nothing, pareto_k_threshold=0.7)
    psis_loo(fit; kwargs...)
    psis_loo(design, draws; chain_ids=nothing, r_eff=nothing, kwargs...)

Standard PSIS-LOO using the reference-checked Zhang–Stephens tail fit. Matrix
rows are draws and columns are observations. Supply contiguous, equally sized
`chain_ids` to estimate relative efficiency from likelihood values, or positive
`r_eff` (scalar or one per observation). Without either, matrix inputs assume
independence and return an explicit warning. Fitted inputs use all retained
chains in their original order; subsampling is refused.

`tail_fraction=.2` and `min_tail_draws=5` are retained compatibility keywords;
other values are rejected because standard PSIS selects its tail from S and
relative efficiency. The diagnostic threshold defaults to .7 and may be set
explicitly. Constant or insufficiently variable tails retain infinite Pareto-k
and a warning, not evidence of perfect precision. Reported pointwise SE is not
MCMC MCSE or a crossed-cluster SE; no refitting or automatic selection occurs.

The former Hill approximation remains available through
`criteria(fit; criteria=(:hill_smoothed_loo,))`. Historical results are unchanged.
"""
function psis_loo(loglik::AbstractMatrix; chain_ids=nothing, r_eff=nothing,
        pareto_k_threshold::Real=.7, tail_fraction::Real=.2, min_tail_draws::Int=5)
    controls = _check_loo_controls(; pareto_k_threshold, tail_fraction, min_tail_draws)
    tail_fraction == .2 && min_tail_draws == 5 || throw(ArgumentError(
        "standard PSIS selects its tail from draw count and r_eff; custom tails require :hill_smoothed_loo"))
    S, N = size(loglik)
    S >= 5 && N >= 1 || throw(ArgumentError("PSIS requires at least five draws and one observation"))
    all(isfinite, loglik) || throw(ArgumentError("loglik contains non-finite values"))
    chain_ids === nothing || r_eff === nothing || throw(ArgumentError("supply chain_ids or r_eff, not both"))
    n_chains = 0
    if chain_ids !== nothing
        length(chain_ids) == S || throw(ArgumentError("chain_ids must label every draw"))
        labels = sort(unique(chain_ids)); n_chains = length(labels)
        labels == collect(1:n_chains) && S % n_chains == 0 &&
            chain_ids == repeat(labels; inner=div(S,n_chains)) ||
            throw(ArgumentError("chain IDs must be complete, contiguous and equally sized"))
        div(S,n_chains) >= 4 || throw(ArgumentError("relative efficiency requires at least four draws per chain"))
    end
    efficiencies = r_eff === nothing ? ones(N) : r_eff isa Real ? fill(Float64(r_eff),N) : Float64.(r_eff)
    length(efficiencies) == N && all(x -> isfinite(x) && x > 0, efficiencies) ||
        throw(ArgumentError("r_eff must be positive and finite, scalar or one value per observation"))
    source = chain_ids !== nothing ? :chain_basic_ess : r_eff !== nothing ? :supplied : :assumed_independent
    elpd=zeros(N); lppd=zeros(N); khat=zeros(N); ess=zeros(N); tails=zeros(Int,N)
    fallback = Int[]
    # Reuse the existing reference-checked kernel without changing specialized paths.
    kernel = Experimental.StarAssociation
    for j in 1:N
        col = Float64.(view(loglik,:,j))
        if chain_ids !== nothing
            arr = reshape(exp.(col .- maximum(col)), div(S,n_chains), n_chains)
            e = Float64(MCMCDiagnosticTools.ess(arr; kind=:basic,
                split_chains=size(arr,1) >= 8 ? 2 : 1)) / S
            if isfinite(e) && e > 0
                efficiencies[j] = e
            else
                push!(fallback,j) # No valid ESS: retain the failure with a computable diagnostic score.
            end
        end
        p = kernel._psis_smooth_log_ratios(-col; r_eff=efficiencies[j])
        elpd[j] = _logsumexp(col .+ p.norm_log_weights)
        lppd[j] = _logmeanexp(col)
        khat[j] = p.pareto_k; ess[j] = p.n_eff; tails[j] = p.tail_len
    end
    bad = findall(>(controls.pareto_k_threshold),khat)
    warnings = Symbol[]
    !isempty(bad) && push!(warnings,:high_pareto_k)
    source === :assumed_independent && push!(warnings,:relative_efficiency_not_supplied)
    !isempty(fallback) && push!(warnings,:relative_efficiency_unavailable)
    p_loo = lppd .- elpd
    return (; criterion=:loo, method=:pareto_smoothed_importance_sampling,
        estimator=:psis_zhang_stephens, psis_smoothing=true, pareto_k_estimator=:zhang_stephens,
        elpd_loo=sum(elpd), p_loo=sum(p_loo), lppd=sum(lppd), looic=-2sum(elpd),
        se_elpd_loo=_pointwise_se(elpd), se_looic=_pointwise_se(-2 .* elpd),
        pointwise=(;elpd_loo=elpd,p_loo,lppd,looic=-2 .* elpd,pareto_k=khat,
            effective_sample_size=ess,tail_draws=tails,r_eff=efficiencies),
        n_draws=S,n_observations=N,pareto_k_threshold=controls.pareto_k_threshold,
        tail_rule=:min_one_fifth_or_three_sqrt_s_over_reff,
        relative_efficiency=source,relative_efficiency_unavailable=fallback,
        bad_pareto_k_count=length(bad),max_pareto_k=maximum(khat),min_effective_sample_size=minimum(ess),
        warning=isempty(warnings) ? :ok : first(warnings),warnings,
        uncertainty=(;mcmc_mcse=:not_computed,standard_error=:pointwise_not_cluster_adjusted),
        reference_psis_validation=:finite_reference_checks)
end

function _common_fit_psis(fit; ndraws=nothing, draw_indices=nothing,
        rng::AbstractRNG=Random.default_rng(), kwargs...)
    ndraws === nothing && draw_indices === nothing || throw(ArgumentError(
        "fitted PSIS requires all retained draws/chains; use a matrix with explicit r_eff for other samples"))
    context = PredictionObservationAdapter._context(fit,nothing,nothing,rng)
    _check_psis_iterations(context.chain_ids,context.iterations)
    _, ll = PredictionObservationAdapter._prediction_arrays(context.design,context.direct,false)
    return psis_loo(ll; chain_ids=context.chain_ids, kwargs...)
end

function _check_psis_iterations(chains, iterations)
    n = length(chains); C = length(unique(chains))
    n > 0 && C > 0 && n % C == 0 && length(iterations) == n &&
        iterations == repeat(1:div(n,C);outer=C) ||
        throw(ArgumentError("PSIS requires complete retained iteration labels in original order"))
    return nothing
end
