# Linearize the sum of log posterior means jointly across ratings. Summing
# pointwise variances would lose the shared posterior-draw covariance.
function _prediction_log_score_mcse(matrix, elpd, chains)
    S,N = size(matrix)
    n = div(S,chains)
    influence = zeros(S)
    magnitude = zeros(S)
    max_share = 0.0
    for i in 1:N
        for s in 1:S
            relative_logp = matrix[s,i] - elpd[i]
            term = expm1(relative_logp)
            influence[s] += term
            magnitude[s] += abs(term)
            max_share = max(max_share, exp(relative_logp)/S)
        end
    end
    finite = all(isfinite,influence) && all(isfinite,magnitude)
    degenerate = finite && maximum(abs,influence) <= 64eps(Float64)*maximum(magnitude)
    status = !finite ? :nonfinite_linearization : chains < 2 ? :insufficient_chains :
        n < 10 ? :insufficient_draws : degenerate || allequal(influence) ?
        :first_order_degenerate : :first_order_approximation
    value = status === :first_order_approximation ?
        _posterior_mcse_value(reshape(influence,n,chains), Statistics.mean) : missing
    if status === :first_order_approximation && (ismissing(value) || value <= 0)
        status = :mcse_unavailable
        value = missing
    end
    return (; value, per_rating=ismissing(value) ? missing : value/N, status,
        method=:mcmc_delta_influence, n_chains=chains, draws_per_chain=n,
        max_draw_probability_share=max_share, convergence_review_required=true,
        curvature_review_required=true, precision_threshold_applied=false)
end

function _prediction_check_independent_samples(groups)
    seen = Set{String}()
    for rows in groups
        hashes = Set(r.source_sample_hash for r in rows if r.source_sample_hash isa AbstractString &&
            !isempty(r.source_sample_hash))
        isempty(intersect(seen,hashes)) || throw(ArgumentError(
            "independent RNG streams cannot be declared for reused sample hashes"))
        union!(seen,hashes)
    end
end

function _prediction_kfold_mcse(rows, complete, independent, n_ratings)
    independent && _prediction_check_independent_samples([[r] for r in rows])
    status = !complete ? :incomplete : !independent ? :fold_rng_independence_not_declared :
        any(r -> ismissing(r.mcmc_error.value), rows) ? :fold_mcse_unavailable :
        :first_order_approximation
    value = status === :first_order_approximation ?
        foldl(hypot,(r.mcmc_error.value for r in rows);init=0.0) : missing
    return (; value, per_rating=ismissing(value) ? missing : value/n_ratings, status,
        method=:independent_fold_delta, independent_fold_rng=independent,
        independence_verified=false, conditioning=:fixed_data_and_split,
        convergence_review_required=true, curvature_review_required=true,
        precision_threshold_applied=false)
end

function _prediction_comparison_mcse(result, reference, complete, baseline, independent, n_ratings)
    left = get(result,:mcmc_error,nothing)
    right = get(reference,:mcmc_error,nothing)
    status = !complete ? :incomplete : baseline ? :baseline_exact_zero :
        !independent ? :model_rng_independence_not_declared :
        left === nothing || right === nothing ? :model_mcse_not_requested :
        ismissing(left.value) || ismissing(right.value) ? :model_mcse_unavailable :
        :first_order_approximation
    value = status === :baseline_exact_zero ? 0.0 : status === :first_order_approximation ?
        hypot(left.value,right.value) : missing
    return (; value, per_rating=ismissing(value) ? missing : value/n_ratings, status,
        method=:independent_model_delta, independent_model_rng=independent,
        independence_verified=false, conditioning=:fixed_data_and_split,
        convergence_review_required=true, curvature_review_required=true,
        precision_threshold_applied=false)
end
