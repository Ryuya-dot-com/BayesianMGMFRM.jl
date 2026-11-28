# mcmc_diagnostics.jl -- Rank-normalized R-hat, ESS, E-BFMI, sampler/block diagnostics, and fit artifacts.

function _sampler_diagnostic_flag(acceptance_rate::Float64,
        n_nonfinite::Int,
        n_divergences,
        n_max_treedepth,
        n_nonfinite_proposals = missing)
    n_nonfinite > 0 && return :nonfinite_log_posterior
    isfinite(acceptance_rate) && 0 <= acceptance_rate <= 1 ||
        return :invalid_acceptance_rate
    !ismissing(n_nonfinite_proposals) && n_nonfinite_proposals > 0 &&
        return :nonfinite_proposals
    !ismissing(n_divergences) && n_divergences > 0 && return :divergent_transitions
    !ismissing(n_max_treedepth) && n_max_treedepth > 0 && return :max_treedepth
    acceptance_rate == 0.0 && return :zero_acceptance
    acceptance_rate == 1.0 && return :all_accepted
    return :ok
end

function _finite_log_posterior_summary(logps)
    finite_values = Float64[]
    for value in logps
        isfinite(value) && push!(finite_values, Float64(value))
    end
    isempty(finite_values) && return (mean = NaN, minimum = NaN, maximum = NaN)
    return (;
        mean = _column_mean(finite_values),
        minimum = minimum(finite_values),
        maximum = maximum(finite_values),
    )
end

function _nt_get(nt::NamedTuple, key::Symbol, default)
    return haskey(nt, key) ? getproperty(nt, key) : default
end

function _chain_sampler_stats(fit::MFRMFit, chain::Int)
    return [row for row in fit.sampler_stats if row.chain == chain]
end

function _maybe_count(rows, predicate)
    isempty(rows) && return missing
    return count(predicate, rows)
end

function _maybe_mean(rows, field::Symbol)
    isempty(rows) && return missing
    value = _stat_mean(rows, field)
    return isfinite(value) ? value : missing
end

function _maybe_max_int(rows, field::Symbol)
    isempty(rows) && return missing
    values = Int[]
    for row in rows
        value = getproperty(row, field)
        ismissing(value) && continue
        push!(values, Int(value))
    end
    isempty(values) && return missing
    return maximum(values)
end

function _ebfmi(energies)
    values = Float64[]
    for value in energies
        ismissing(value) && return missing
        converted = Float64(value)
        isfinite(converted) || return missing
        push!(values, converted)
    end
    length(values) >= 3 || return missing
    mean_energy = _column_mean(values)
    denom = sum((value - mean_energy)^2 for value in values) / (length(values) - 1)
    isfinite(denom) && denom > 0 || return missing
    numerator = sum((values[i] - values[i - 1])^2 for i in 2:length(values)) / (length(values) - 1)
    result = numerator / denom
    return isfinite(result) && result >= 0 ? result : missing
end

function _chain_sampler_summary(fit::MFRMFit, chain::Int)
    rows = _chain_sampler_stats(fit, chain)
    max_depth = _nt_get(fit.sampler_controls, :max_depth, missing)
    random_walk = fit.sampler === :random_walk_metropolis
    return (;
        n_divergences = random_walk ? 0 : _maybe_count(rows, row -> row.numerical_error),
        n_nonfinite_proposals = random_walk && !isempty(rows) &&
            all(row -> hasproperty(row, :nonfinite_proposal), rows) ?
            count(row -> row.nonfinite_proposal, rows) : missing,
        n_max_treedepth = ismissing(max_depth) ?
            missing :
            _maybe_count(rows, row -> !ismissing(row.tree_depth) && row.tree_depth >= max_depth),
        mean_n_steps = _maybe_mean(rows, :n_steps),
        mean_tree_depth = _maybe_mean(rows, :tree_depth),
        max_tree_depth = _maybe_max_int(rows, :tree_depth),
        mean_step_size = _maybe_mean(rows, :step_size),
        e_bfmi = _ebfmi((row.hamiltonian_energy for row in rows)),
    )
end

"""
    sampler_diagnostics(fit; phase = :retained)

Return chain-level sampler diagnostics for a fitted minimal MFRM object.
Rows include retained draw counts, warmup, step size, chain acceptance rate,
finite log-posterior counts, and log-posterior summaries. This complements
`mcmc_diagnostics`, which reports parameter-level R-hat and ESS. When the
AdvancedHMC/NUTS backend is used, rows also include divergent-transition,
tree-depth, step-size, and E-BFMI fields where available.
For random-walk fits, `n_nonfinite_proposals` counts rejected non-finite
proposals among retained iterations; these are not NUTS divergences. The count
is `missing` for older fits without proposal telemetry and for other samplers.

Use `phase = :warmup` for separate chain-level warmup counts from new fits.
AdvancedHMC, Turing and CmdStan report divergences, maximum-depth hits and
nonfinite log densities. Generalized GMFRM/MGMFRM fits support AdvancedHMC
and CmdStan. Random walk reports `n_nonfinite_proposals` during burn-in;
it does not adapt its proposal scale. Its NUTS event fields are `missing`
because they do not apply. All rows report expected/observed iterations.
`coverage` is `:recorded`, `:not_run` (zero warmup), or `:not_recorded`
(history unavailable); unavailable counts are `missing`.
Warmup events do not enter posterior summaries, R-hat/ESS or
retained-draw warning flags. No warmup pass/fail rule is applied.
Older Turing fits without an explicit `sampler_controls.nadapts` record have
unavailable history even when their requested warmup was zero: that request
did not reliably disable adaptation.
These summaries survive `save_fit_cache`/`load_fit_cache`; warmup parameter
draws are not retained. The default `phase = :retained` preserves the existing
diagnostic rows.
"""
function sampler_diagnostics(fit::MFRMFit; phase::Symbol = :retained)
    phase === :warmup && return _fit_warmup_diagnostics(fit)
    phase === :retained || throw(ArgumentError("phase must be :retained or :warmup"))
    draws_per_chain = _fit_draws_per_chain(fit)
    nchains = length(fit.chain_acceptance_rate)
    rows = NamedTuple[]
    for chain in 1:nchains
        draw_rows = ((chain - 1) * draws_per_chain + 1):(chain * draws_per_chain)
        logps = @view fit.log_posterior[draw_rows]
        summary = _finite_log_posterior_summary(logps)
        n_finite = count(isfinite, logps)
        n_nonfinite = length(logps) - n_finite
        sampler_summary = _chain_sampler_summary(fit, chain)
        push!(rows, (;
            diagnostic_row = :sampler_chain,
            parameter_space = :identified,
            diagnostic_method = :sampler_chain_summary,
            diagnostic_status = :recorded,
            chain,
            backend = fit.backend,
            sampler = fit.sampler,
            n_draws = draws_per_chain,
            warmup = fit.warmup,
            step_size = fit.step_size,
            first_iteration = first(@view fit.iterations[draw_rows]),
            last_iteration = last(@view fit.iterations[draw_rows]),
            acceptance_rate = fit.chain_acceptance_rate[chain],
            mean_log_posterior = summary.mean,
            minimum_log_posterior = summary.minimum,
            maximum_log_posterior = summary.maximum,
            n_finite_log_posterior = n_finite,
            n_nonfinite_log_posterior = n_nonfinite,
            n_nonfinite_proposals = sampler_summary.n_nonfinite_proposals,
            n_divergences = sampler_summary.n_divergences,
            n_max_treedepth = sampler_summary.n_max_treedepth,
            mean_n_steps = sampler_summary.mean_n_steps,
            mean_tree_depth = sampler_summary.mean_tree_depth,
            max_tree_depth = sampler_summary.max_tree_depth,
            mean_step_size = sampler_summary.mean_step_size,
            e_bfmi = sampler_summary.e_bfmi,
            flag = _sampler_diagnostic_flag(fit.chain_acceptance_rate[chain],
                n_nonfinite,
                sampler_summary.n_divergences,
                sampler_summary.n_max_treedepth,
                sampler_summary.n_nonfinite_proposals),
        ))
    end
    return rows
end

function _mcmc_parameter_flag(diagnostic,
        rhat_threshold::Float64,
        ess_threshold::Float64)
    diagnostic.rank_normalized_status === :ok ||
        return diagnostic.rank_normalized_status
    isfinite(diagnostic.rank_normalized_rhat) &&
        diagnostic.rank_normalized_rhat > rhat_threshold &&
        return :mcmc_warning
    isfinite(diagnostic.bulk_ess) && diagnostic.bulk_ess < ess_threshold &&
        return :mcmc_warning
    isfinite(diagnostic.tail_ess) && diagnostic.tail_ess < ess_threshold &&
        return :mcmc_warning
    return :ok
end

function _classical_compatibility_parameter_flag(diagnostic,
        rhat_threshold::Float64,
        ess_threshold::Float64)
    diagnostic.classical_compatibility_status === :ok ||
        return diagnostic.classical_compatibility_status
    isfinite(diagnostic.rhat) && diagnostic.rhat > rhat_threshold &&
        return :mcmc_warning
    isfinite(diagnostic.ess) && diagnostic.ess < ess_threshold &&
        return :mcmc_warning
    return :ok
end

"""
    mcmc_diagnostics(fit::MFRMFit; split_chains = true,
                     rhat_threshold = 1.01, ess_threshold = 400)

Return parameter-level convergence diagnostics for the current fitted draws.
Rows include rank-normalized split R-hat, its bulk and folded components,
bulk ESS, and tail ESS at the joint 10% tail probability. The compatibility
fields `rhat` and `ess` retain the previous classical split R-hat and
autocorrelation ESS values. The primary `flag` and `rank_normalized_flag`
apply only the modern contract; `classical_compatibility_flag` records the
previous diagnostic result without adding an undeclared quality gate.

These diagnostics require at least two independent chains. Rank-normalized
ESS requires more than four draws per diagnostic chain after optional
splitting; shorter runs return `flag = :insufficient_draws`. Non-finite or
degenerate draws are never passed through as apparently usable diagnostics.
Use `sampler_diagnostics` for backend-specific fields such as divergent
transitions and tree depth.
"""
function mcmc_diagnostics(fit::MFRMFit;
        split_chains::Bool = true,
        rhat_threshold::Real = 1.01,
        ess_threshold::Real = 400)
    checked = _check_diagnostic_thresholds(rhat_threshold, ess_threshold)
    values = _chain_draw_array(fit)
    original_iterations, original_chains, nparams = size(values)
    diagnostic_values = split_chains && original_chains >= 2 ?
        _split_chain_array(values) :
        values
    diagnostic_iterations, diagnostic_chains, _ = size(diagnostic_values)
    rows = NamedTuple[]
    for param in 1:nparams
        diagnostic = _mcmc_parameter_metrics(
            values,
            param;
            split_chains,
        )
        rank_normalized_flag = _mcmc_parameter_flag(
            diagnostic,
            checked.rhat_threshold,
            checked.ess_threshold,
        )
        classical_compatibility_flag =
            _classical_compatibility_parameter_flag(
                diagnostic,
                checked.rhat_threshold,
                checked.ess_threshold,
            )
        push!(rows, (;
            diagnostic_row = :parameter,
            parameter_space = :identified,
            diagnostic_contract = _MCMC_DIAGNOSTIC_CONTRACT,
            diagnostic_method = _mcmc_diagnostic_method(split_chains),
            diagnostic_status = :rank_normalized_available,
            parameter = fit.design.parameter_names[param],
            quality_gate_applicable = true,
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
            total_draws = size(fit.draws, 1),
            split_chains_requested = split_chains,
            split_chains = split_chains && original_chains >= 2 && original_iterations >= 4,
            rank_normalized_flag,
            classical_compatibility_flag,
            flag = rank_normalized_flag,
        ))
    end
    return rows
end

function _check_diagnostic_thresholds(rhat_threshold::Real, ess_threshold::Real)
    checked_rhat = Float64(rhat_threshold)
    checked_ess = Float64(ess_threshold)
    isfinite(checked_rhat) && checked_rhat > 1 ||
        throw(ArgumentError(
            "rhat_threshold must be finite and greater than 1",
        ))
    isfinite(checked_ess) && checked_ess > 0 ||
        throw(ArgumentError(
            "ess_threshold must be finite and positive",
        ))
    return (rhat_threshold = checked_rhat, ess_threshold = checked_ess)
end

function _finite_extreme(values, reducer)
    finite_values = [Float64(value) for value in values if isfinite(value)]
    isempty(finite_values) && return NaN
    return reducer(finite_values)
end

_quality_gate_applicable(row) =
    !hasproperty(row, :quality_gate_applicable) ||
    row.quality_gate_applicable

function _mcmc_metric_summary(rows,
        rhat_threshold::Float64,
        ess_threshold::Float64)
    applicable_rows = filter(_quality_gate_applicable, rows)
    return (;
        n_parameters = length(rows),
        n_quality_gate_parameters = length(applicable_rows),
        n_structurally_fixed_parameters =
            count(row -> !_quality_gate_applicable(row), rows),
        max_rhat = _finite_extreme(
            (row.rhat for row in applicable_rows),
            maximum,
        ),
        min_ess = _finite_extreme(
            (row.ess for row in applicable_rows),
            minimum,
        ),
        max_rank_normalized_rhat = _finite_extreme(
            (row.rank_normalized_rhat for row in applicable_rows),
            maximum,
        ),
        min_bulk_ess = _finite_extreme(
            (row.bulk_ess for row in applicable_rows),
            minimum,
        ),
        min_tail_ess = _finite_extreme(
            (row.tail_ess for row in applicable_rows),
            minimum,
        ),
        n_bad_rhat = count(row ->
            isfinite(row.rhat) && row.rhat > rhat_threshold,
            applicable_rows),
        n_low_ess = count(row ->
            isfinite(row.ess) && row.ess < ess_threshold,
            applicable_rows),
        n_bad_rank_normalized_rhat = count(row ->
            isfinite(row.rank_normalized_rhat) &&
                row.rank_normalized_rhat > rhat_threshold,
            applicable_rows),
        n_low_bulk_ess = count(row ->
            isfinite(row.bulk_ess) && row.bulk_ess < ess_threshold,
            applicable_rows),
        n_low_tail_ess = count(row ->
            isfinite(row.tail_ess) && row.tail_ess < ess_threshold,
            applicable_rows),
        n_insufficient_chains = count(row ->
            row.flag === :insufficient_chains, applicable_rows),
        n_insufficient_draws = count(row ->
            row.flag === :insufficient_draws, applicable_rows),
        n_nonfinite_parameters = count(row ->
            row.flag === :nonfinite_draws, applicable_rows),
        n_degenerate_parameters = count(row ->
            row.flag === :degenerate_draws, applicable_rows),
        n_classical_insufficient_chains = count(row ->
            row.classical_compatibility_flag === :insufficient_chains,
            applicable_rows),
        n_classical_nonfinite_parameters = count(row ->
            row.classical_compatibility_flag === :nonfinite_draws,
            applicable_rows),
        n_classical_degenerate_parameters = count(row ->
            row.classical_compatibility_flag === :degenerate_draws,
            applicable_rows),
        n_classical_compatibility_warnings = count(row ->
            row.classical_compatibility_flag !== :ok,
            applicable_rows),
    )
end

function _generalized_mcmc_metric_fields(
        raw_metrics,
        direct_metrics,
        combined_metrics)
    return (;
        # Preserve the established raw-space meaning of classical fields.
        max_rhat = raw_metrics.max_rhat,
        min_ess = raw_metrics.min_ess,
        n_bad_rhat = raw_metrics.n_bad_rhat,
        n_low_ess = raw_metrics.n_low_ess,
        n_classical_insufficient_chains =
            raw_metrics.n_classical_insufficient_chains,
        n_classical_nonfinite_parameters =
            raw_metrics.n_classical_nonfinite_parameters,
        n_classical_degenerate_parameters =
            raw_metrics.n_classical_degenerate_parameters,
        n_classical_compatibility_warnings =
            raw_metrics.n_classical_compatibility_warnings,
        # Modern fields conservatively cover raw and direct parameter spaces.
        max_rank_normalized_rhat =
            combined_metrics.max_rank_normalized_rhat,
        min_bulk_ess = combined_metrics.min_bulk_ess,
        min_tail_ess = combined_metrics.min_tail_ess,
        n_bad_rank_normalized_rhat =
            combined_metrics.n_bad_rank_normalized_rhat,
        n_low_bulk_ess = combined_metrics.n_low_bulk_ess,
        n_low_tail_ess = combined_metrics.n_low_tail_ess,
        # Preserve raw-space status counts and expose explicit overall counts.
        n_insufficient_chains = raw_metrics.n_insufficient_chains,
        n_insufficient_draws = raw_metrics.n_insufficient_draws,
        n_nonfinite_parameters = raw_metrics.n_nonfinite_parameters,
        n_degenerate_parameters = raw_metrics.n_degenerate_parameters,
        n_overall_insufficient_chains =
            combined_metrics.n_insufficient_chains,
        n_overall_insufficient_draws =
            combined_metrics.n_insufficient_draws,
        n_overall_nonfinite_parameters =
            combined_metrics.n_nonfinite_parameters,
        n_overall_degenerate_parameters =
            combined_metrics.n_degenerate_parameters,
        raw_diagnostic_metrics = raw_metrics,
        direct_diagnostic_metrics = direct_metrics,
        combined_diagnostic_metrics = combined_metrics,
    )
end

function _mcmc_metric_warning(metrics)
    return metrics.n_bad_rank_normalized_rhat > 0 ||
        metrics.n_low_bulk_ess > 0 ||
        metrics.n_low_tail_ess > 0
end

function _classical_compatibility_metric_warning(metrics)
    return metrics.n_bad_rhat > 0 || metrics.n_low_ess > 0
end

function _parameter_block_flag(n_parameters::Int, metrics)
    n_parameters == 0 && return :empty_block
    metrics.n_quality_gate_parameters == 0 &&
        metrics.n_structurally_fixed_parameters > 0 &&
        return :structurally_fixed
    metrics.n_insufficient_chains > 0 && return :insufficient_chains
    metrics.n_insufficient_draws > 0 && return :insufficient_draws
    metrics.n_nonfinite_parameters > 0 && return :nonfinite_draws
    metrics.n_degenerate_parameters > 0 && return :degenerate_draws
    _mcmc_metric_warning(metrics) && return :mcmc_warning
    return :ok
end

function _classical_compatibility_block_flag(n_parameters::Int, metrics)
    n_parameters == 0 && return :empty_block
    metrics.n_quality_gate_parameters == 0 &&
        metrics.n_structurally_fixed_parameters > 0 &&
        return :structurally_fixed
    metrics.n_classical_insufficient_chains > 0 && return :insufficient_chains
    metrics.n_classical_nonfinite_parameters > 0 && return :nonfinite_draws
    metrics.n_classical_degenerate_parameters > 0 && return :degenerate_draws
    _classical_compatibility_metric_warning(metrics) && return :mcmc_warning
    return :ok
end

function _parameter_block_diagnostics(fit::MFRMFit,
        parameter_rows;
        split_chains::Bool,
        rhat_threshold::Float64,
        ess_threshold::Float64)
    row_by_name = Dict(row.parameter => row for row in parameter_rows)
    blocks = sort(collect(keys(fit.design.blocks)); by = string)
    rows = NamedTuple[]
    for block in blocks
        range = fit.design.blocks[block]
        indices = collect(range)
        names = isempty(indices) ? String[] : copy(fit.design.parameter_names[indices])
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
        push!(rows, (;
            diagnostic_row = :parameter_block,
            parameter_space = :identified,
            diagnostic_contract = _MCMC_DIAGNOSTIC_CONTRACT,
            diagnostic_method = _mcmc_diagnostic_method(split_chains),
            diagnostic_status = :rank_normalized_available,
            block,
            first_parameter = isempty(indices) ? missing : first(indices),
            last_parameter = isempty(indices) ? missing : last(indices),
            n_parameters,
            n_quality_gate_parameters,
            n_structurally_fixed_parameters,
            quality_gate_applicable = n_quality_gate_parameters > 0,
            parameter_names = names,
            n_chains = length(fit.chain_acceptance_rate),
            draws_per_chain = _fit_draws_per_chain(fit),
            total_draws = size(fit.draws, 1),
            split_chains_requested = split_chains,
            split_chains = split_chains &&
                length(fit.chain_acceptance_rate) >= 2 &&
                _fit_draws_per_chain(fit) >= 4,
            autocovariance_maxlag = n_parameters == 0 ? missing :
                first(block_rows).autocovariance_maxlag,
            rhat_threshold,
            ess_threshold,
            max_rhat = n_parameters == 0 ? missing : metrics.max_rhat,
            min_ess = n_parameters == 0 ? missing : metrics.min_ess,
            max_rank_normalized_rhat = n_parameters == 0 ? missing :
                metrics.max_rank_normalized_rhat,
            min_bulk_ess = n_parameters == 0 ? missing :
                metrics.min_bulk_ess,
            min_tail_ess = n_parameters == 0 ? missing :
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

"""
    parameter_block_diagnostics(fit::MFRMFit; split_chains = true,
                                rhat_threshold = 1.01,
                                ess_threshold = 400)

Summarize MCMC convergence diagnostics by identified parameter block. Rows
aggregate the parameter-level R-hat and ESS diagnostics for blocks such as
`:person`, `:rater`, `:item`, and `:thresholds`, while retaining block
parameter names and machine-readable pass/fail counts. Empty blocks are
returned with `flag = :empty_block` so reports can distinguish absent design
terms from failed diagnostics.
"""
function parameter_block_diagnostics(fit::MFRMFit;
        split_chains::Bool = true,
        rhat_threshold::Real = 1.01,
        ess_threshold::Real = 400)
    checked = _check_diagnostic_thresholds(rhat_threshold, ess_threshold)
    parameter_rows = mcmc_diagnostics(fit;
        split_chains,
        rhat_threshold = checked.rhat_threshold,
        ess_threshold = checked.ess_threshold)
    return _parameter_block_diagnostics(fit, parameter_rows;
        split_chains,
        rhat_threshold = checked.rhat_threshold,
        ess_threshold = checked.ess_threshold)
end


function _sum_nonmissing(values)
    total = 0
    seen = false
    for value in values
        ismissing(value) && continue
        total += Int(value)
        seen = true
    end
    return seen ? total : missing
end

function _min_nonmissing(values)
    finite_values = [Float64(value) for value in values if !ismissing(value) && isfinite(value)]
    isempty(finite_values) && return missing
    return minimum(finite_values)
end

function _ebfmi_coverage(rows)
    values = Float64[
        row.e_bfmi for row in rows
        if !ismissing(row.e_bfmi) && isfinite(row.e_bfmi)
    ]
    n_e_bfmi_expected = length(rows)
    n_e_bfmi_available = length(values)
    n_e_bfmi_unavailable = n_e_bfmi_expected - n_e_bfmi_available
    return (;
        e_bfmi = isempty(values) ? missing : minimum(values),
        n_e_bfmi_expected,
        n_e_bfmi_available,
        n_e_bfmi_unavailable,
        e_bfmi_complete =
            n_e_bfmi_expected > 0 && n_e_bfmi_unavailable == 0,
    )
end

function _diagnostic_row_policy(; family::Symbol, parameter_spaces)
    return (;
        schema = "bayesianmgmfrm.diagnostic_row_policy.v1",
        family,
        sampler_row = :sampler_chain,
        parameter_row = :parameter,
        block_row = :parameter_block,
        parameter_spaces = Tuple(parameter_spaces),
        diagnostic_contract = _MCMC_DIAGNOSTIC_CONTRACT,
        diagnostic_contract_details = _mcmc_diagnostic_contract_record(),
        rhat_method = :rank_normalized,
        rhat_components = (
            :bulk_rank_normalized_rhat,
            :folded_rank_normalized_rhat,
        ),
        primary_rhat_field = :rank_normalized_rhat,
        ess_method = :bulk_and_tail,
        primary_ess_fields = (:bulk_ess, :tail_ess),
        tail_probability = _RANK_NORMALIZED_TAIL_PROBABILITY,
        autocovariance_maxlag_policy = :all_available_lags,
        minimum_draws_per_diagnostic_chain_for_ess = 5,
        quality_gate_applicability_field = :quality_gate_applicable,
        structurally_fixed_status = :structurally_fixed,
        compatibility_rhat_field = :rhat,
        compatibility_rhat_method = :classical_split,
        compatibility_ess_field = :ess,
        compatibility_ess_method = :autocorrelation,
        primary_flag_field = :rank_normalized_flag,
        compatibility_flag_field = :classical_compatibility_flag,
        rhat_ess_status = :rank_normalized_available,
        rank_normalized_rhat_available = true,
        bulk_tail_ess_available = true,
        e_bfmi_field = :e_bfmi,
        e_bfmi_completeness_field = :e_bfmi_complete,
        e_bfmi_chain_coverage_required = true,
        informational_flags = (
            :ok,
            :empty_block,
            :structurally_fixed,
        ),
        failure_flags = (
            :direct_transform_warning,
            :sampler_warning,
            :mcmc_warning,
            :insufficient_chains,
            :insufficient_draws,
            :nonfinite_draws,
            :degenerate_draws,
        ),
    )
end

"""
    diagnostics(fit::MFRMFit; view = :full, split_chains = true,
                rhat_threshold = 1.01, ess_threshold = 400)

Return a single diagnostic surface for the current minimal Bayesian fitting
path. The result includes chain-level sampler rows from `sampler_diagnostics`,
parameter-level rows from `mcmc_diagnostics`, block-level rows from
`parameter_block_diagnostics`, and a compact machine-readable summary with
rank-normalized R-hat, bulk ESS, tail ESS, compatibility metrics, and
pass/fail counts. For the AdvancedHMC-backed NUTS path, the summary also
reports divergent-transition counts, max-tree-depth hits, and the minimum
available E-BFMI estimate across chains. The fields `n_e_bfmi_expected`,
`n_e_bfmi_available`, `n_e_bfmi_unavailable`, and `e_bfmi_complete` distinguish
that compatibility minimum from an all-chain E-BFMI gate. A chain is
unavailable when any retained energy value is missing or non-finite.

Generalized diagnostic surfaces also include direct constrained rows.
Coordinates fixed by a declared zero-dimensional raw transform remain visible
with `diagnostic_status = :structurally_fixed` and
`quality_gate_applicable = false`; they do not enter convergence extrema or
failure counts. Constrained coordinates reconstructed from estimable raw
coordinates remain quality-gate applicable.

The surrounding version-1 diagnostic payload is discriminated by its nested
`diagnostic_contract`. Rows without
`:rank_normalized_rhat_bulk_tail_ess_v1` are pre-modern compatibility records
and must not be relabeled as modern evidence. Under the modern contract,
`flag` aliases `rank_normalized_flag`; use `classical_compatibility_flag` when
the previous classical result is specifically required.

The compatibility default `view = :full` returns the complete diagnostic
surface. `view = :public` keeps reader-facing diagnostic results while
carrying explicit `family` and `stability` fields in a compact portable
schema.
"""
function diagnostics(fit::MFRMFit;
        view::Symbol = :full,
        split_chains::Bool = true,
        rhat_threshold::Real = 1.01,
        ess_threshold::Real = 400)
    view in (:full, :public) ||
        throw(ArgumentError("view must be :full or :public"))
    checked = _check_diagnostic_thresholds(rhat_threshold, ess_threshold)

    sampler_rows = sampler_diagnostics(fit)
    parameter_rows = mcmc_diagnostics(fit;
        split_chains,
        rhat_threshold = checked.rhat_threshold,
        ess_threshold = checked.ess_threshold)
    block_rows = _parameter_block_diagnostics(fit, parameter_rows;
        split_chains,
        rhat_threshold = checked.rhat_threshold,
        ess_threshold = checked.ess_threshold)
    n_sampler_warnings = count(row -> row.flag !== :ok, sampler_rows)
    n_block_warnings = count(row -> row.flag in
        (:insufficient_chains, :insufficient_draws, :nonfinite_draws,
            :degenerate_draws,
            :mcmc_warning), block_rows)
    n_empty_blocks = count(row -> row.flag === :empty_block, block_rows)
    n_nonfinite_log_posterior = sum(row.n_nonfinite_log_posterior for row in sampler_rows)
    n_nonfinite_proposals = all(row -> !ismissing(row.n_nonfinite_proposals), sampler_rows) ?
        sum(row.n_nonfinite_proposals for row in sampler_rows) : missing
    n_divergences = _sum_nonmissing(row.n_divergences for row in sampler_rows)
    n_max_treedepth = _sum_nonmissing(row.n_max_treedepth for row in sampler_rows)
    e_bfmi_coverage = _ebfmi_coverage(sampler_rows)
    metrics = _mcmc_metric_summary(
        parameter_rows,
        checked.rhat_threshold,
        checked.ess_threshold,
    )

    flag = if n_sampler_warnings > 0 || n_nonfinite_log_posterior > 0
        :sampler_warning
    elseif metrics.n_insufficient_chains > 0
        :insufficient_chains
    elseif metrics.n_insufficient_draws > 0
        :insufficient_draws
    elseif metrics.n_nonfinite_parameters > 0 ||
            metrics.n_degenerate_parameters > 0 ||
            _mcmc_metric_warning(metrics)
        :mcmc_warning
    else
        :ok
    end

    surface = (;
        schema = "bayesianmgmfrm.diagnostics.v1",
        backend = fit.backend,
        sampler = fit.sampler,
        diagnostic_row_policy = _diagnostic_row_policy(;
            family = :mfrm,
            parameter_spaces = (:identified,)),
        summary = (;
            diagnostic_contract = _MCMC_DIAGNOSTIC_CONTRACT,
            diagnostic_contract_details = _mcmc_diagnostic_contract_record(),
            flag,
            passed = flag === :ok,
            classical_compatibility_flag =
                _classical_compatibility_block_flag(
                    length(parameter_rows), metrics),
            n_chains = length(fit.chain_acceptance_rate),
            draws_per_chain = _fit_draws_per_chain(fit),
            total_draws = size(fit.draws, 1),
            split_chains_requested = split_chains,
            split_chains = split_chains &&
                length(fit.chain_acceptance_rate) >= 2 &&
                _fit_draws_per_chain(fit) >= 4,
            rhat_threshold = checked.rhat_threshold,
            ess_threshold = checked.ess_threshold,
            metrics...,
            n_block_warnings,
            n_empty_blocks,
            n_sampler_warnings,
            n_nonfinite_log_posterior,
            n_nonfinite_proposals,
            n_divergences,
            n_max_treedepth,
            e_bfmi_coverage...,
        ),
        sampler_rows,
        parameter_rows,
        block_rows,
    )
    return view === :full ? surface :
        _public_reader_payload(
            surface;
            schema = "bayesianmgmfrm.diagnostics_public.v1",
            family = :mfrm,
            stability = :stable,
        )
end

function sampler_diagnostics(fit::Union{GMFRMFit,MGMFRMFit}; phase::Symbol = :retained)
    phase === :warmup && return _fit_warmup_diagnostics(fit)
    phase === :retained || throw(ArgumentError("phase must be :retained or :warmup"))
    return fit.diagnostic_surface.sampler_rows
end

function _check_stored_generalized_diagnostic_contract(surface, family_label::String)
    summary = surface.summary
    expected_contract = _mcmc_diagnostic_contract_record()
    hasproperty(summary, :diagnostic_contract) &&
        summary.diagnostic_contract === _MCMC_DIAGNOSTIC_CONTRACT ||
        throw(ArgumentError(
            "$family_label fit stores an older MCMC diagnostic contract; " *
            "refresh the fit or its cache before requesting diagnostics",
        ))
    hasproperty(summary, :diagnostic_contract_details) &&
        isequal(summary.diagnostic_contract_details, expected_contract) ||
        throw(ArgumentError(
            "$family_label fit was created under a different MCMC " *
            "diagnostic dependency or operation-order contract; refresh the " *
            "fit or its cache before requesting diagnostics",
        ))
    all(field -> hasproperty(summary, field), (
            :n_e_bfmi_expected,
            :n_e_bfmi_available,
            :n_e_bfmi_unavailable,
            :e_bfmi_complete,
        )) &&
        summary.n_e_bfmi_expected == summary.n_chains &&
        summary.n_e_bfmi_available + summary.n_e_bfmi_unavailable ==
            summary.n_e_bfmi_expected &&
        summary.e_bfmi_complete ===
            (summary.n_e_bfmi_expected > 0 &&
                summary.n_e_bfmi_unavailable == 0) ||
        throw(ArgumentError(
            "$family_label fit stores incomplete E-BFMI chain coverage; " *
            "refresh the fit or its cache before requesting diagnostics",
        ))
    required_fields = (
        :diagnostic_contract,
        :rank_normalized_rhat,
        :bulk_rank_normalized_rhat,
        :folded_rank_normalized_rhat,
        :bulk_ess,
        :tail_ess,
        :rank_normalized_flag,
        :classical_compatibility_flag,
        :quality_gate_applicable,
        :split_chains_requested,
    )
    parameter_rows = (surface.parameter_rows, surface.direct_parameter_rows)
    all(row -> all(field -> hasproperty(row, field), required_fields) &&
            row.diagnostic_contract === _MCMC_DIAGNOSTIC_CONTRACT &&
            row.diagnostic_method === _mcmc_diagnostic_method(
                row.split_chains_requested,
            ) &&
            ((row.quality_gate_applicable &&
                    row.diagnostic_status ===
                        :rank_normalized_available) ||
                (!row.quality_gate_applicable &&
                    row.diagnostic_status === :structurally_fixed &&
                    row.rank_normalized_flag === :structurally_fixed &&
                    row.classical_compatibility_flag ===
                        :structurally_fixed)),
        Iterators.flatten(parameter_rows)) || throw(ArgumentError(
        "$family_label fit stores incomplete MCMC diagnostic rows; " *
        "refresh the fit or its cache before requesting diagnostics",
    ))
    block_rows = (surface.block_rows, surface.direct_block_rows)
    all(row -> all(field -> hasproperty(row, field), (
                :diagnostic_contract,
                :rank_normalized_flag,
                :classical_compatibility_flag,
                :quality_gate_applicable,
                :n_quality_gate_parameters,
                :n_structurally_fixed_parameters,
                :split_chains_requested,
            )) &&
            row.diagnostic_contract === _MCMC_DIAGNOSTIC_CONTRACT &&
            row.diagnostic_method === _mcmc_diagnostic_method(
                row.split_chains_requested,
            ) &&
            ((row.diagnostic_status === :rank_normalized_available &&
                    (row.quality_gate_applicable ||
                        row.flag === :empty_block)) ||
                (row.diagnostic_status === :structurally_fixed &&
                    !row.quality_gate_applicable &&
                    row.n_quality_gate_parameters == 0 &&
                    row.n_structurally_fixed_parameters > 0 &&
                    row.rank_normalized_flag === :structurally_fixed &&
                    row.classical_compatibility_flag ===
                        :structurally_fixed)),
        Iterators.flatten(block_rows)) || throw(ArgumentError(
        "$family_label fit stores incomplete MCMC diagnostic block rows; " *
        "refresh the fit or its cache before requesting diagnostics",
    ))
    return nothing
end

function _check_gmfrm_fit_diagnostic_policy(fit::GMFRMFit;
        split_chains::Bool,
        rhat_threshold::Real,
        ess_threshold::Real)
    checked = _check_diagnostic_thresholds(rhat_threshold, ess_threshold)
    _check_stored_generalized_diagnostic_contract(
        fit.diagnostic_surface,
        "GMFRM",
    )
    summary = fit.diagnostic_surface.summary
    actual_split = split_chains &&
        length(fit.chain_acceptance_rate) >= 2 &&
        _fit_draws_per_chain(fit) >= 4
    hasproperty(summary, :split_chains_requested) &&
        summary.split_chains_requested == split_chains &&
        summary.split_chains == actual_split &&
        summary.rhat_threshold == checked.rhat_threshold &&
        summary.ess_threshold == checked.ess_threshold ||
        throw(ArgumentError(
            "GMFRM fit diagnostics are recorded at fit time; " *
            "use the original split_chains, rhat_threshold, and ess_threshold",
        ))
    return checked
end

function mcmc_diagnostics(fit::GMFRMFit;
        split_chains::Bool = true,
        rhat_threshold::Real = 1.01,
        ess_threshold::Real = 400)
    _check_gmfrm_fit_diagnostic_policy(fit;
        split_chains,
        rhat_threshold,
        ess_threshold)
    return fit.diagnostic_surface.parameter_rows
end

function parameter_block_diagnostics(fit::GMFRMFit;
        split_chains::Bool = true,
        rhat_threshold::Real = 1.01,
        ess_threshold::Real = 400)
    _check_gmfrm_fit_diagnostic_policy(fit;
        split_chains,
        rhat_threshold,
        ess_threshold)
    return fit.diagnostic_surface.block_rows
end

function _gmfrm_fit_weighted_sufficient_score(fit::GMFRMFit; interval::Real = 0.95)
    0.0 < Float64(interval) < 1.0 || throw(ArgumentError("interval must be in (0, 1)"))
    lo = 0.5 * (1.0 - Float64(interval))
    hi = 1.0 - lo
    d = fit.design.spec.data
    blks = fit.design.blocks
    a_cols = blks[:item_discrimination]
    c_cols = blks[:rater_consistency]
    draws = fit.direct_draws
    S = size(draws, 1)
    chains = max(length(fit.chain_acceptance_rate), 1)
    P = length(d.person_levels)
    obs_by_p = [Int[] for _ in 1:P]
    for n in 1:d.n
        push!(obs_by_p[d.person[n]], n)
    end
    w_sum_draws = zeros(Float64, S, P)
    w_mean_draws = fill(NaN, S, P)
    @inbounds for s in 1:S
        for p in 1:P
            ns = obs_by_p[p]
            isempty(ns) && continue
            ws_cat = 0.0
            ws_num = 0.0
            w_tot = 0.0
            for n in ns
                i = d.item[n]
                r = d.rater[n]
                w_n = draws[s, c_cols[r]] * draws[s, a_cols[i]]
                ws_cat += w_n * Float64(d.category[n] - 1)
                ws_num += w_n * Float64(d.score[n])
                w_tot += w_n
            end
            w_sum_draws[s, p] = ws_cat
            w_mean_draws[s, p] = w_tot > 0.0 ? (ws_num / w_tot) : NaN
        end
    end
    rows = map(1:P) do p
        ns = obs_by_p[p]
        m_p = length(ns)
        raw_s = sum((Float64(d.score[n]) for n in ns); init = 0.0)
        raw_m = m_p > 0 ? raw_s / m_p : NaN
        v_ws = view(w_sum_draws, :, p)
        v_wm = view(w_mean_draws, :, p)
        wm_mcse = (m_p > 0 && S % chains == 0 && div(S, chains) >= 4 && all(isfinite, v_wm)) ?
            MCMCDiagnosticTools.mcse(reshape(v_wm, div(S, chains), chains)) : NaN
        (;
            person = d.person_levels[p],
            dimension = 1,
            n_ratings = m_p,
            raw_sum = raw_s,
            raw_mean = raw_m,
            weighted_sufficient_mean = Statistics.mean(v_ws),
            weighted_sufficient_sd = Statistics.std(v_ws),
            weighted_sufficient_lower = Statistics.quantile(v_ws, lo),
            weighted_sufficient_upper = Statistics.quantile(v_ws, hi),
            weighted_average_mean = m_p > 0 ? Statistics.mean(v_wm) : NaN,
            weighted_average_sd = m_p > 0 ? Statistics.std(v_wm) : NaN,
            weighted_average_lower = m_p > 0 ? Statistics.quantile(v_wm, lo) : NaN,
            weighted_average_upper = m_p > 0 ? Statistics.quantile(v_wm, hi) : NaN,
            weighted_average_mcse = wm_mcse,
            adjustment_vs_raw_mean = m_p > 0 ? (Statistics.mean(v_wm) - raw_m) : NaN,
        )
    end
    return (;
        schema = "bayesianmgmfrm.weighted_sufficient_score.v1",
        kind = :weighted_sufficient_score,
        family = :gmfrm,
        dimension = 1,
        interval = Float64(interval),
        n_persons = P,
        n_draws = S,
        rows,
        qualification = qualify(fit),
    )
end

function diagnostics(fit::GMFRMFit;
        kind::Symbol = :mcmc,
        interval::Real = 0.95,
        view::Symbol = :full,
        split_chains::Bool = true,
        rhat_threshold::Real = 1.01,
        ess_threshold::Real = 400)
    if kind === :weighted_sufficient_score
        return _gmfrm_fit_weighted_sufficient_score(fit; interval)
    elseif kind !== :mcmc
        throw(ArgumentError("GMFRMFit diagnostics supports kind = :mcmc or :weighted_sufficient_score; got $(repr(kind))"))
    end
    view in (:full, :public) ||
        throw(ArgumentError("view must be :full or :public"))
    _check_gmfrm_fit_diagnostic_policy(fit;
        split_chains,
        rhat_threshold,
        ess_threshold)
    surface = fit.diagnostic_surface
    diagnostic_surface = (;
        schema = "bayesianmgmfrm.gmfrm_experimental_fit_diagnostics.v1",
        family = :gmfrm,
        scope = :scalar_gmfrm_fit_ready_candidate,
        public_fit = true,
        experimental_public = true,
        backend = fit.backend,
        sampler = fit.sampler,
        diagnostic_row_policy = _diagnostic_row_policy(;
            family = :gmfrm,
            parameter_spaces = (:raw_unconstrained, :direct_constrained)),
        parameter_layout = surface.parameter_layout,
        summary = surface.summary,
        sampler_rows = surface.sampler_rows,
        parameter_rows = surface.parameter_rows,
        block_rows = surface.block_rows,
        direct_constraint_rows = surface.direct_constraint_rows,
        direct_parameter_rows = surface.direct_parameter_rows,
        direct_block_rows = surface.direct_block_rows,
    )
    return view === :full ? diagnostic_surface :
        _public_reader_payload(
            merge(diagnostic_surface, (;
                parameter_layout = fit_ready_parameter_layout(
                    fit.design;
                    view = :public,
                ),
            ));
            schema = "bayesianmgmfrm.diagnostics_public.v1",
            family = :gmfrm,
            stability = :experimental,
        )
end

function _check_mgmfrm_fit_diagnostic_policy(fit::MGMFRMFit;
        split_chains::Bool,
        rhat_threshold::Real,
        ess_threshold::Real)
    checked = _check_diagnostic_thresholds(rhat_threshold, ess_threshold)
    _check_stored_generalized_diagnostic_contract(
        fit.diagnostic_surface,
        "guarded MGMFRM",
    )
    summary = fit.diagnostic_surface.summary
    actual_split = split_chains &&
        length(fit.chain_acceptance_rate) >= 2 &&
        _fit_draws_per_chain(fit) >= 4
    hasproperty(summary, :split_chains_requested) &&
        summary.split_chains_requested == split_chains &&
        summary.split_chains == actual_split &&
        summary.rhat_threshold == checked.rhat_threshold &&
        summary.ess_threshold == checked.ess_threshold ||
        throw(ArgumentError(
            "guarded MGMFRM fit diagnostics are recorded at fit time; " *
            "use the original split_chains, rhat_threshold, and ess_threshold",
        ))
    return checked
end

function mcmc_diagnostics(fit::MGMFRMFit;
        split_chains::Bool = true,
        rhat_threshold::Real = 1.01,
        ess_threshold::Real = 400)
    _check_mgmfrm_fit_diagnostic_policy(fit;
        split_chains,
        rhat_threshold,
        ess_threshold)
    return fit.diagnostic_surface.parameter_rows
end

function parameter_block_diagnostics(fit::MGMFRMFit;
        split_chains::Bool = true,
        rhat_threshold::Real = 1.01,
        ess_threshold::Real = 400)
    _check_mgmfrm_fit_diagnostic_policy(fit;
        split_chains,
        rhat_threshold,
        ess_threshold)
    return fit.diagnostic_surface.block_rows
end

"""
    diagnostics(fit::MGMFRMFit; include_location = false, view = :full, ...)

Return the saved parameter and sampler assessment. With `include_location = true`,
also compute `location_rows` and `location_summary` for fitted-person ability
means, item difficulties, loading-weighted ability means and their differences.
These equally weighted finite-panel quantities distinguish movement in a common
location from movement in the response-relevant differences. Active loadings are
used at every draw, including within-item Q structures. They are not population
means, a new centering constraint, or a replacement for the original `summary`.
Both views retain these optional diagnostics; default output is unchanged.
"""
function diagnostics(fit::MGMFRMFit;
        view::Symbol = :full,
        include_location::Bool = false,
        split_chains::Bool = true,
        rhat_threshold::Real = 1.01,
        ess_threshold::Real = 400)
    view in (:full, :public) ||
        throw(ArgumentError("view must be :full or :public"))
    checked = _check_mgmfrm_fit_diagnostic_policy(fit;
        split_chains,
        rhat_threshold,
        ess_threshold)
    surface = fit.diagnostic_surface
    location = include_location ? _mgmfrm_location_diagnostics(fit;
        split_chains, rhat_threshold = checked.rhat_threshold,
        ess_threshold = checked.ess_threshold) : (;)
    diagnostic_surface = (;
        location...,
        schema = "bayesianmgmfrm.mgmfrm_guarded_local_fit_diagnostics.v1",
        family = :mgmfrm,
        scope = :minimal_confirmatory_mgmfrm_candidate,
        public_fit = true,
        experimental_public = true,
        fit_ready = true,
        guarded_local_fit = true,
        backend = fit.backend,
        sampler = fit.sampler,
        diagnostic_row_policy = _diagnostic_row_policy(;
            family = :mgmfrm,
            parameter_spaces = (:raw_unconstrained, :direct_constrained)),
        parameter_layout = surface.parameter_layout,
        initialization_policy = surface.initialization_policy,
        initialization_rows = surface.initialization_rows,
        fixed_q_invariance_rows = _mgmfrm_fixed_q_invariance_rows(
            fit.design,
            surface;
            prior = fit.prior,
        ),
        summary = surface.summary,
        sampler_rows = surface.sampler_rows,
        parameter_rows = surface.parameter_rows,
        block_rows = surface.block_rows,
        direct_constraint_rows = surface.direct_constraint_rows,
        direct_parameter_rows = surface.direct_parameter_rows,
        direct_block_rows = surface.direct_block_rows,
    )
    return view === :full ? diagnostic_surface :
        _public_reader_payload(
            merge(diagnostic_surface, (;
                parameter_layout = fit_ready_parameter_layout(
                    fit.design;
                    view = :public,
                ),
                initialization_rows =
                    _public_mgmfrm_initialization_rows(
                        diagnostic_surface.initialization_rows,
                    ),
                fixed_q_invariance_rows =
                    _public_mgmfrm_fixed_q_invariance_rows(
                        diagnostic_surface.fixed_q_invariance_rows,
                    ),
            ));
            schema = "bayesianmgmfrm.diagnostics_public.v1",
            family = :mgmfrm,
            stability = :experimental,
        )
end

function _model_manifest(fit::MFRMFit, diagnostic_summary)
    base = model_manifest(fit.design)
    return (;
        schema = "bayesianmgmfrm.model_manifest.v1",
        object = :fit,
        status_policy = _fit_status_policy(fit),
        data = base.data,
        validation = base.validation,
        spec = base.spec,
        design = base.design,
        fit = fit_metadata(fit),
        model_surface_audit = model_surface_audit(fit),
        rating_design = base.rating_design,
        diagnostics = diagnostic_summary,
    )
end

function _public_fit_model_manifest(fit, diagnostic_summary)
    return (;
        schema = "bayesianmgmfrm.model_manifest_public.v1",
        object = :fit,
        family = fit.design.spec.family,
        model = model_manifest(fit.design; view = :public),
        fit = _public_fit_report_project_value(fit_metadata(fit)),
        diagnostics = _public_fit_report_project_value(diagnostic_summary),
    )
end

function model_manifest(fit::MFRMFit; view::Symbol = :full)
    view in (:full, :public) ||
        throw(ArgumentError("view must be :full or :public"))
    diagnostic_summary = diagnostics(fit).summary
    return view === :full ? _model_manifest(fit, diagnostic_summary) :
        _public_fit_model_manifest(fit, diagnostic_summary)
end

function _model_manifest(fit::GMFRMFit, diagnostic_summary)
    base = model_manifest(fit.design)
    return (;
        schema = "bayesianmgmfrm.model_manifest.v1",
        object = :fit,
        family = :gmfrm,
        scope = :scalar_gmfrm_fit_ready_candidate,
        public_fit = true,
        experimental_public = true,
        fit_ready = true,
        status_policy = _fit_status_policy(fit),
        data = base.data,
        validation = base.validation,
        spec = base.spec,
        design = base.design,
        fit = fit_metadata(fit),
        model_surface_audit = model_surface_audit(fit),
        rating_design = base.rating_design,
        diagnostics = diagnostic_summary,
    )
end

function model_manifest(fit::GMFRMFit; view::Symbol = :full)
    view in (:full, :public) ||
        throw(ArgumentError("view must be :full or :public"))
    diagnostic_summary = diagnostics(fit).summary
    return view === :full ? _model_manifest(fit, diagnostic_summary) :
        _public_fit_model_manifest(fit, diagnostic_summary)
end

function _model_manifest(fit::MGMFRMFit, diagnostic_summary)
    base = model_manifest(fit.design)
    return (;
        schema = "bayesianmgmfrm.model_manifest.v1",
        object = :fit,
        family = :mgmfrm,
        scope = :minimal_confirmatory_mgmfrm_candidate,
        public_fit = true,
        experimental_public = true,
        guarded_local_fit = true,
        fit_ready = true,
        status_policy = _fit_status_policy(fit),
        data = base.data,
        validation = base.validation,
        spec = base.spec,
        design = base.design,
        fit = fit_metadata(fit),
        model_surface_audit = model_surface_audit(fit),
        rating_design = base.rating_design,
        diagnostics = diagnostic_summary,
    )
end

function model_manifest(fit::MGMFRMFit; view::Symbol = :full)
    view in (:full, :public) ||
        throw(ArgumentError("view must be :full or :public"))
    diagnostic_summary = diagnostics(fit).summary
    return view === :full ? _model_manifest(fit, diagnostic_summary) :
        _public_fit_model_manifest(fit, diagnostic_summary)
end

function _fit_rng_control(fit)
    controls = fit.sampler_controls
    haskey(controls, :rng) && return controls.rng
    return (;
        algorithm = missing,
        seed = missing,
        replayable = false,
    )
end

function _artifact_inclusion_flag(include::Bool)
    return include ? :included : :omitted
end

function _fit_evidence_artifact_schema_policy(artifact_kind::Symbol,
        status_policy;
        include_environment::Bool,
        include_cache_provenance::Bool = false)
    return evidence_artifact_schema_policy(artifact_kind;
        include_environment,
        include_cache_provenance,
        raw_data_status = :not_included,
        unsupported_claims = status_policy.blocked_claims)
end

"""
    fit_artifact(fit; view = :full, include_draws = false,
                 include_log_posterior = include_draws,
                 include_sampler_stats = false,
                 include_environment = true,
                 include_packages = false,
                 include_environment_paths = false,
                 split_chains = true,
                 rhat_threshold = 1.01,
                 ess_threshold = 400)

Return a reproducibility artifact for a fitted MFRM, scalar GMFRM,
or fixed-Q MGMFRM object. The artifact combines the model
manifest, selected diagnostic surface, posterior summary, sampler controls, RNG
replay metadata, and optional environment metadata. Draws, log-posterior values,
and sampler-stat rows are omitted by default to keep the artifact compact; set
the corresponding `include_*` keyword to retain them for a cached-draw report
path. Environment metadata omits machine-local paths by default;
`include_environment_paths = true` is an explicit private-record opt-in. The
compatibility default `view = :full` retains the complete archive contract and
is intended for private reproduction records. Use `view = :public` when sharing
a reader-facing, path-free projection with its own verifiable content hash.
For `MFRMFit`, `GMFRMFit` and `MGMFRMFit`, `include_draws = true` also
includes `draw_index.chain_ids` and `draw_index.iterations`, aligned with every
stored matrix row. MFRM columns follow `parameter_names`; generalized raw and
direct columns follow their respective name vectors and share the row index.
The public view retains generalized `direct_draws` only, and actual
priors/settings in `fit_metadata`. Earlier
artifacts may lack these additive fields; do not infer a missing row index.
These additions do not apply to the separate recorded-result artifact types.

Stored fixed-coefficient multidimensional MFRM results support both views and
use their recorded diagnostic settings. Their artifact retains both free and
reconstructed unit-logit summaries and the source sample identity. Estimate with `BayesianMGMFRM.Experimental.fit`.
New full artifacts use `mfrm_fixed_q_fit_artifact.v2`; cache readers also validate
old v1 artifacts with their original metadata and hashes unchanged.
"""
function fit_artifact(fit::MFRMFit;
        view::Symbol = :full,
        include_draws::Bool = false,
        include_log_posterior::Bool = include_draws,
        include_sampler_stats::Bool = false,
        include_environment::Bool = true,
        include_packages::Bool = false,
        include_environment_paths::Bool = false,
        split_chains::Bool = true,
        rhat_threshold::Real = 1.01,
        ess_threshold::Real = 400)
    view in (:full, :public) ||
        throw(ArgumentError("view must be :full or :public"))
    diagnostic_surface = diagnostics(fit;
        split_chains,
        rhat_threshold,
        ess_threshold)
    manifest = _model_manifest(fit, diagnostic_surface.summary)
    evidence_policy = _fit_evidence_artifact_schema_policy(
        :fit_artifact,
        manifest.status_policy;
        include_environment)
    rng = _fit_rng_control(fit)
    artifact_policy = (;
        draws = _artifact_inclusion_flag(include_draws),
        log_posterior = _artifact_inclusion_flag(include_log_posterior),
        sampler_stats = _artifact_inclusion_flag(include_sampler_stats),
        environment = _artifact_inclusion_flag(include_environment),
        package_status = include_environment && include_packages ? :included : :omitted,
    )
    reproducibility = (;
        data_signature = fit.design.spec.validation.data_signature,
        rng,
        replayable_rng = _nt_get(rng, :replayable, false) === true,
        sampler_controls = fit.sampler_controls,
        diagnostic_policy = (;
            diagnostic_contract =
                diagnostic_surface.summary.diagnostic_contract,
            diagnostic_contract_details =
                diagnostic_surface.summary.diagnostic_contract_details,
            split_chains_requested =
                diagnostic_surface.summary.split_chains_requested,
            split_chains = diagnostic_surface.summary.split_chains,
            rhat_threshold = diagnostic_surface.summary.rhat_threshold,
            ess_threshold = diagnostic_surface.summary.ess_threshold,
        ),
        artifact_policy,
    )
    environment = include_environment ?
        evidence_metadata(;
            include_packages,
            include_paths = include_environment_paths,
        ) :
        nothing
    artifact = _with_archive_metadata((;
        schema = "bayesianmgmfrm.fit_artifact.v1",
        object = :fit_artifact,
        created_at = string(now()),
        evidence_artifact_schema_policy = evidence_policy,
        manifest,
        diagnostics = diagnostic_surface,
        posterior_summary = posterior_summary(fit),
        reproducibility,
        environment,
        parameter_names = copy(fit.design.parameter_names),
        draws = include_draws ? copy(fit.draws) : nothing,
        draw_index = include_draws ? (; chain_ids = copy(fit.chain_ids),
            iterations = copy(fit.iterations)) : nothing,
        log_posterior = include_log_posterior ? copy(fit.log_posterior) : nothing,
        sampler_stats = include_sampler_stats ? copy(fit.sampler_stats) : nothing,
    ); label = :fit_artifact)
    return view === :full ? artifact :
        _public_fit_artifact_projection(artifact, fit)
end

function fit_artifact(fit::GMFRMFit;
        view::Symbol = :full,
        include_draws::Bool = false,
        include_log_posterior::Bool = include_draws,
        include_sampler_stats::Bool = false,
        include_environment::Bool = true,
        include_packages::Bool = false,
        include_environment_paths::Bool = false,
        split_chains::Bool = true,
        rhat_threshold::Real = 1.01,
        ess_threshold::Real = 400)
    view in (:full, :public) ||
        throw(ArgumentError("view must be :full or :public"))
    diagnostic_surface = diagnostics(fit;
        split_chains,
        rhat_threshold,
        ess_threshold)
    manifest = _model_manifest(fit, diagnostic_surface.summary)
    evidence_policy = _fit_evidence_artifact_schema_policy(
        :gmfrm_experimental_fit_artifact,
        manifest.status_policy;
        include_environment)
    base_manifest = model_manifest(fit.design)
    raw_manifest = base_manifest.design.raw_parameterization
    promotion = raw_manifest.promotion_candidate
    experimental_decision = promotion.experimental_public_api
    rng = _fit_rng_control(fit)
    artifact_policy = (;
        raw_draws = _artifact_inclusion_flag(include_draws),
        direct_draws = _artifact_inclusion_flag(include_draws),
        log_posterior = _artifact_inclusion_flag(include_log_posterior),
        sampler_stats = _artifact_inclusion_flag(include_sampler_stats),
        environment = _artifact_inclusion_flag(include_environment),
        package_status = include_environment && include_packages ? :included : :omitted,
    )
    reproducibility = (;
        data_signature = fit.design.spec.validation.data_signature,
        rng,
        replayable_rng = _nt_get(rng, :replayable, false) === true,
        sampler_controls = fit.sampler_controls,
        diagnostic_policy = (;
            diagnostic_contract =
                diagnostic_surface.summary.diagnostic_contract,
            diagnostic_contract_details =
                diagnostic_surface.summary.diagnostic_contract_details,
            split_chains_requested =
                diagnostic_surface.summary.split_chains_requested,
            split_chains = diagnostic_surface.summary.split_chains,
            rhat_threshold = diagnostic_surface.summary.rhat_threshold,
            ess_threshold = diagnostic_surface.summary.ess_threshold,
        ),
        artifact_policy,
    )
    environment = include_environment ?
        evidence_metadata(;
            include_packages,
            include_paths = include_environment_paths,
        ) :
        nothing
    parameter_layout = diagnostic_surface.parameter_layout
    raw_posterior_rows = posterior_summary(fit)
    direct_posterior_rows = direct_posterior_summary(fit)
    raw_prior_control_manifest =
        _resolved_generalized_raw_prior_control_manifest(
            experimental_decision.raw_prior_control_manifest,
            fit.prior,
        )
    artifact = _with_archive_metadata((;
        schema = "bayesianmgmfrm.gmfrm_experimental_fit_artifact.v1",
        object = :fit_artifact,
        family = :gmfrm,
        scope = :scalar_gmfrm_fit_ready_candidate,
        status = :experimental_public_fit_artifact,
        public_fit = true,
        experimental_public = true,
        fit_ready = true,
        created_at = string(now()),
        evidence_artifact_schema_policy = evidence_policy,
        entrypoint = _EXPERIMENTAL_CANONICAL_ENTRYPOINT,
        legacy_entrypoint = _EXPERIMENTAL_LEGACY_ENTRYPOINT,
        public_target_label = experimental_decision.public_target_label,
        public_target_description = experimental_decision.public_target_description,
        internal_target_constructor = experimental_decision.internal_target_constructor,
        internal_sampler_diagnostic_constructor =
            experimental_decision.internal_sampler_diagnostic_constructor,
        density_space = :raw_unconstrained,
        raw_prior_control_manifest,
        parameter_layout,
        raw_parameter_names = copy(fit.diagnostic_surface.raw_parameter_names),
        direct_parameter_names =
            copy(fit.diagnostic_surface.direct_parameter_names),
        raw_to_direct_transform = parameter_layout.transforms,
        sampler_controls = fit.sampler_controls,
        diagnostics = diagnostic_surface,
        pointwise_loglikelihood = copy(fit.direct_pointwise_loglikelihood),
        caveat_docs_artifact = experimental_decision.caveat_docs_artifact,
        fixture_provenance = experimental_decision.fit_artifact_contract.provenance_rows,
        manifest,
        posterior_summary = raw_posterior_rows,
        direct_posterior_summary = direct_posterior_rows,
        raw_posterior_row_schema = _posterior_summary_row_schema(
            raw_posterior_rows;
            family = :gmfrm,
            scope = :scalar_gmfrm_fit_ready_candidate,
            parameter_space = :raw_unconstrained,
            summary_function = :posterior_summary,
            parameter_names = parameter_layout.raw_parameter_names,
            blocks = parameter_layout.raw_blocks,
            layout = parameter_layout,
        ),
        direct_posterior_row_schema = _posterior_summary_row_schema(
            direct_posterior_rows;
            family = :gmfrm,
            scope = :scalar_gmfrm_fit_ready_candidate,
            parameter_space = :constrained_direct,
            summary_function = :direct_posterior_summary,
            parameter_names = parameter_layout.constrained_parameter_names,
            blocks = parameter_layout.constrained_blocks,
            layout = parameter_layout,
        ),
        reproducibility,
        environment,
        raw_draws = include_draws ? copy(fit.draws) : nothing,
        draw_index = include_draws ? (; chain_ids = copy(fit.chain_ids),
            iterations = copy(fit.iterations)) : nothing,
        direct_draws = include_draws ? copy(fit.direct_draws) : nothing,
        log_posterior = include_log_posterior ? copy(fit.log_posterior) : nothing,
        sampler_stats = include_sampler_stats ? copy(fit.sampler_stats) : nothing,
    ); label = :gmfrm_experimental_fit_artifact)
    return view === :full ? artifact :
        _public_fit_artifact_projection(artifact, fit)
end

function fit_artifact(fit::MGMFRMFit;
        view::Symbol = :full,
        include_draws::Bool = false,
        include_log_posterior::Bool = include_draws,
        include_sampler_stats::Bool = false,
        include_environment::Bool = true,
        include_packages::Bool = false,
        include_environment_paths::Bool = false,
        split_chains::Bool = true,
        rhat_threshold::Real = 1.01,
        ess_threshold::Real = 400)
    view in (:full, :public) ||
        throw(ArgumentError("view must be :full or :public"))
    diagnostic_surface = diagnostics(fit;
        split_chains,
        rhat_threshold,
        ess_threshold)
    manifest = _model_manifest(fit, diagnostic_surface.summary)
    evidence_policy = _fit_evidence_artifact_schema_policy(
        :mgmfrm_experimental_fit_artifact,
        manifest.status_policy;
        include_environment)
    base_manifest = model_manifest(fit.design)
    raw_manifest = base_manifest.design.raw_parameterization
    confirmatory = raw_manifest.confirmatory_candidate
    experimental_decision = confirmatory.experimental_public_api_decision
    rng = _fit_rng_control(fit)
    artifact_policy = (;
        raw_draws = _artifact_inclusion_flag(include_draws),
        direct_draws = _artifact_inclusion_flag(include_draws),
        log_posterior = _artifact_inclusion_flag(include_log_posterior),
        sampler_stats = _artifact_inclusion_flag(include_sampler_stats),
        environment = _artifact_inclusion_flag(include_environment),
        package_status = include_environment && include_packages ? :included : :omitted,
    )
    reproducibility = (;
        data_signature = fit.design.spec.validation.data_signature,
        rng,
        replayable_rng = _nt_get(rng, :replayable, false) === true,
        sampler_controls = fit.sampler_controls,
        diagnostic_policy = (;
            diagnostic_contract =
                diagnostic_surface.summary.diagnostic_contract,
            diagnostic_contract_details =
                diagnostic_surface.summary.diagnostic_contract_details,
            split_chains_requested =
                diagnostic_surface.summary.split_chains_requested,
            split_chains = diagnostic_surface.summary.split_chains,
            rhat_threshold = diagnostic_surface.summary.rhat_threshold,
            ess_threshold = diagnostic_surface.summary.ess_threshold,
        ),
        artifact_policy,
    )
    environment = include_environment ?
        evidence_metadata(;
            include_packages,
            include_paths = include_environment_paths,
        ) :
        nothing
    parameter_layout = diagnostic_surface.parameter_layout
    raw_posterior_rows = posterior_summary(fit)
    direct_posterior_rows = direct_posterior_summary(fit)
    raw_prior_control_manifest =
        _resolved_generalized_raw_prior_control_manifest(
            experimental_decision.raw_prior_control_manifest,
            fit.prior,
        )
    artifact = _with_archive_metadata((;
        schema = "bayesianmgmfrm.mgmfrm_experimental_fit_artifact.v1",
        object = :fit_artifact,
        family = :mgmfrm,
        scope = :minimal_confirmatory_mgmfrm_candidate,
        status = :experimental_public_fit_artifact,
        public_fit = true,
        experimental_public = true,
        guarded_local_fit = true,
        fit_ready = true,
        created_at = string(now()),
        evidence_artifact_schema_policy = evidence_policy,
        density_space = :raw_unconstrained,
        entrypoint = _EXPERIMENTAL_CANONICAL_ENTRYPOINT,
        legacy_entrypoint = _EXPERIMENTAL_LEGACY_ENTRYPOINT,
        guarded_local_entrypoint = :_fit_guarded_mgmfrm,
        public_target_label = experimental_decision.public_target_label,
        public_target_description = experimental_decision.public_target_description,
        internal_target_constructor = experimental_decision.internal_target_constructor,
        internal_sampler_diagnostic_constructor =
            experimental_decision.internal_sampler_diagnostic_constructor,
        target = :_mgmfrm_guarded_local_fit_logdensity,
        q_matrix = _q_matrix_manifest(fit.design.spec.q_matrix),
        latent_correlation = :identity_fixed,
        _mgmfrm_ability_prior_metadata(fit.prior)...,
        design_prior_scope = :source_reference_not_resolved_fit_prior,
        initialization_policy = diagnostic_surface.initialization_policy,
        initialization_rows = diagnostic_surface.initialization_rows,
        fixed_q_invariance_rows = _mgmfrm_fixed_q_invariance_rows(
            fit.design,
            diagnostic_surface;
            prior = fit.prior,
        ),
        raw_prior_control_manifest,
        parameter_layout,
        raw_parameter_names = copy(fit.diagnostic_surface.raw_parameter_names),
        direct_parameter_names =
            copy(fit.diagnostic_surface.direct_parameter_names),
        raw_to_direct_transform = parameter_layout.transforms,
        sampler_controls = fit.sampler_controls,
        diagnostics = diagnostic_surface,
        pointwise_loglikelihood = copy(fit.direct_pointwise_loglikelihood),
        caveat_docs_artifact = experimental_decision.caveat_docs_artifact,
        fixture_provenance = experimental_decision.fit_artifact_contract.provenance_rows,
        manifest,
        posterior_summary = raw_posterior_rows,
        direct_posterior_summary = direct_posterior_rows,
        raw_posterior_row_schema = _posterior_summary_row_schema(
            raw_posterior_rows;
            family = :mgmfrm,
            scope = :minimal_confirmatory_mgmfrm_candidate,
            parameter_space = :raw_unconstrained,
            summary_function = :posterior_summary,
            parameter_names = parameter_layout.raw_parameter_names,
            blocks = parameter_layout.raw_blocks,
            layout = parameter_layout,
        ),
        direct_posterior_row_schema = _posterior_summary_row_schema(
            direct_posterior_rows;
            family = :mgmfrm,
            scope = :minimal_confirmatory_mgmfrm_candidate,
            parameter_space = :constrained_direct,
            summary_function = :direct_posterior_summary,
            parameter_names = parameter_layout.constrained_parameter_names,
            blocks = parameter_layout.constrained_blocks,
            layout = parameter_layout,
        ),
        reproducibility,
        environment,
        raw_draws = include_draws ? copy(fit.draws) : nothing,
        draw_index = include_draws ? (; chain_ids = copy(fit.chain_ids),
            iterations = copy(fit.iterations)) : nothing,
        direct_draws = include_draws ? copy(fit.direct_draws) : nothing,
        log_posterior = include_log_posterior ? copy(fit.log_posterior) : nothing,
        sampler_stats = include_sampler_stats ? copy(fit.sampler_stats) : nothing,
    ); label = :mgmfrm_experimental_fit_artifact)
    return view === :full ? artifact :
        _public_fit_artifact_projection(artifact, fit)
end
