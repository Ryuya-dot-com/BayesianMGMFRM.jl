# Equally weighted fitted-person means; no extra population parameters.
function _mgmfrm_location_coordinates(design::FacetDesign, direct::AbstractMatrix)
    _mgmfrm_direct_draws_for_prediction(design, direct, "MGMFRM location diagnostics")
    spec, data = design.spec, design.spec.data
    D, S = spec.dimensions, size(direct, 1)
    means = hcat([vec(mean(direct[:, design.blocks[:person][d:D:end]]; dims = 2))
        for d in 1:D]...)
    rows = NamedTuple[]
    for d in 1:D
        push!(rows, (; parameter = "person_mean[$(spec.dimension_labels[d])]",
            block = :person_mean, dimension = d, dimension_label = spec.dimension_labels[d],
            item = nothing, item_label = missing, values = means[:, d]))
    end
    indices = _mgmfrm_source_loading_index_matrix(design)
    for i in eachindex(data.item_levels)
        weighted = zeros(S)
        for d in 1:D
            indices[i, d] == 0 && continue
            weighted .+= direct[:, indices[i, d]] .* means[:, d]
        end
        difficulty = direct[:, design.blocks[:item][i]]
        active = findall(spec.q_matrix[i, :])
        dimension = length(active) == 1 ? only(active) : nothing
        label = dimension === nothing ? missing : spec.dimension_labels[dimension]
        for (block, values) in ((:item_location, difficulty),
                (:loading_weighted_person_mean, weighted),
                (:item_minus_loading_weighted_person_mean, difficulty - weighted))
            push!(rows, (; parameter = "$block[$(data.item_levels[i])]", block,
                dimension, dimension_label = label, item = i,
                item_label = data.item_levels[i], values))
        end
    end
    all(row -> all(isfinite, row.values), rows) ||
        throw(ArgumentError("nonfinite derived MGMFRM location"))
    return rows
end

function _mgmfrm_location_diagnostics(fit::MGMFRMFit;
        split_chains, rhat_threshold, ess_threshold)
    chains, n = length(fit.chain_acceptance_rate), _fit_draws_per_chain(fit)
    fit.chain_ids == repeat(1:chains; inner = n) &&
        fit.iterations == repeat(1:n; outer = chains) ||
        throw(ArgumentError("MGMFRM location diagnostics require the saved chain/iteration order"))
    blueprint = _mgmfrm_fit_ready_candidate_blueprint(fit.design)
    size(fit.draws) == (chains * n, blueprint.n_parameters) && all(isfinite, fit.draws) &&
        fit.diagnostic_surface.raw_parameter_names == blueprint.parameter_names ||
        throw(ArgumentError("invalid MGMFRM raw draws or coordinate names"))
    direct = reduce(vcat, [permutedims(_mgmfrm_source_constrained_params_from_unconstrained(
        fit.design, collect(raw), blueprint)) for raw in eachrow(fit.draws)])
    size(direct) == size(fit.direct_draws) &&
        all(isapprox(a, b; atol = 1e-12, rtol = 1e-12) for (a, b) in zip(direct, fit.direct_draws)) ||
        throw(ArgumentError("saved MGMFRM direct draws disagree with raw reconstruction"))
    coordinates = _mgmfrm_location_coordinates(fit.design, direct)
    metrics = _candidate_mcmc_diagnostic_rows(hcat(getproperty.(coordinates, :values)...),
        String[row.parameter for row in coordinates], chains;
        parameter_space = :derived_model_location, split_chains, rhat_threshold, ess_threshold)
    rows = [merge(metric, Base.structdiff(coordinate, (; values = nothing)),
        (; fixed = false, derived = true)) for (metric, coordinate) in zip(metrics, coordinates)]
    summary = _mcmc_metric_summary(rows, rhat_threshold, ess_threshold)
    flag = _generalized_candidate_summary_flag(0, 0, 0, 0, summary, summary)
    return (; location_status = :computed, location_rows = rows,
        location_summary = (; summary..., flag),
        location_interpretation = "Means equally weight the fitted persons in each dimension. For item i, the weighted mean is sum_d(a[i,d] * mean_person(theta[d])) over active Q cells, before multiplication by 1.7 and rater consistency. Subtracting it from item difficulty cancels a joint ability/item location shift, including within-item Q. These are finite-panel summaries, not population means. The declared priors still anchor separate locations; no centering, prior change or parameter/sampler warning override is performed.")
end
