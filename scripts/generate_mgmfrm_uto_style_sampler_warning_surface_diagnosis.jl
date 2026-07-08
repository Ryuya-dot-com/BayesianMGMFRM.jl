#!/usr/bin/env julia

using Dates
using JSON3
using SHA
using TOML

import BayesianMGMFRM

module SamplerPilot
include(joinpath(@__DIR__,
    "generate_mgmfrm_uto_style_sampler_remediation_critical_pilot.jl"))
end

const ROOT = normpath(joinpath(@__DIR__, ".."))
const DEFAULT_REMEDIATION_JSON =
    joinpath(ROOT, "artifacts", "uto_style_sampler_remediation_critical_pilot",
        "uto_style_sampler_remediation_critical_pilot.json")
const DEFAULT_OUTPUT_JSON =
    joinpath(ROOT, "artifacts",
        "uto_style_sampler_warning_surface_diagnosis",
        "uto_style_sampler_warning_surface_diagnosis.json")
const DEFAULT_OUTPUT_MD =
    joinpath(ROOT, "artifacts",
        "uto_style_sampler_warning_surface_diagnosis",
        "uto_style_sampler_warning_surface_diagnosis.md")

include(joinpath(@__DIR__, "local_json.jl"))

const ReplicatedQCategory = SamplerPilot.SplitGrid.ReplicatedQCategory
const QMisspec = ReplicatedQCategory.QMisspec
const OUTPUT_SCHEMA =
    "bayesianmgmfrm.mgmfrm_uto_style_sampler_warning_surface_diagnosis.v1"
const MCMC_MODEL_NAMES = ReplicatedQCategory.MCMC_MODEL_NAMES

function usage()
    return """
    Diagnose the warning surface behind Uto-style critical-cell MCMC flags.

    This reruns the sampler-remediation critical cells and saves the diagnostic
    counts that score rows intentionally omit: R-hat/ESS failures, block-level
    warnings, divergent transitions, tree-depth hits, E-BFMI, nonfinite
    log-density counts, and direct-transform failures. It is a local diagnostic
    only; public threshold, model-weight, and Q-revision claims remain blocked.

    Usage:
      julia --project=. scripts/generate_mgmfrm_uto_style_sampler_warning_surface_diagnosis.jl [options]

    Options:
      --remediation-json PATH  Sampler-remediation pilot artifact.
      --output-json PATH       JSON artifact path.
      --output-md PATH         Markdown report path.
      --split-offsets LIST     Comma-separated split offsets. Default: artifact/default.
      --max-cells N            Limit selected cells for smoke runs. Default: all.
      --n-persons N            Number of persons. Default: 6.
      --n-raters N             Number of raters. Default: 3.
      --heldout-fraction X     Observation holdout fraction. Default: 0.17.
      --chains N               MCMC chains. Default: 4.
      --warmup-per-chain N     Warmup iterations per chain. Default: 64.
      --draws-per-chain N      Posterior draws per chain. Default: 64.
      --target-acceptance X    NUTS target acceptance. Default: 0.85.
      --prior-profile NAME     Internal source prior profile: default, tight, or diffuse.
                              Default: default.
      --progress               Show sampler progress.
    """
end

function parse_int_list(text::AbstractString, option::AbstractString)
    values = Int[]
    for part in split(text, ",")
        stripped = strip(part)
        isempty(stripped) && continue
        push!(values, parse(Int, stripped))
    end
    isempty(values) && error("$option must contain at least one value")
    length(unique(values)) == length(values) ||
        error("$option values must be unique")
    return values
end

function parse_args(args)
    remediation_json = DEFAULT_REMEDIATION_JSON
    output_json = DEFAULT_OUTPUT_JSON
    output_md = DEFAULT_OUTPUT_MD
    split_offsets = copy(SamplerPilot.DEFAULT_SPLIT_OFFSETS)
    max_cells = 0
    n_persons = 6
    n_raters = 3
    heldout_fraction = 0.17
    chains = 4
    warmup_per_chain = 64
    draws_per_chain = 64
    target_acceptance = 0.85
    prior_profile = :default
    progress = false

    index = 1
    while index <= length(args)
        arg = args[index]
        if arg == "--remediation-json"
            index < length(args) || error("--remediation-json requires a path")
            remediation_json = abspath(args[index + 1])
            index += 2
        elseif arg == "--output-json"
            index < length(args) || error("--output-json requires a path")
            output_json = abspath(args[index + 1])
            index += 2
        elseif arg == "--output-md"
            index < length(args) || error("--output-md requires a path")
            output_md = abspath(args[index + 1])
            index += 2
        elseif arg == "--split-offsets"
            index < length(args) || error("--split-offsets requires a list")
            split_offsets = parse_int_list(args[index + 1], "--split-offsets")
            index += 2
        elseif arg == "--max-cells"
            index < length(args) || error("--max-cells requires an integer")
            max_cells = parse(Int, args[index + 1])
            index += 2
        elseif arg == "--n-persons"
            index < length(args) || error("--n-persons requires an integer")
            n_persons = parse(Int, args[index + 1])
            index += 2
        elseif arg == "--n-raters"
            index < length(args) || error("--n-raters requires an integer")
            n_raters = parse(Int, args[index + 1])
            index += 2
        elseif arg == "--heldout-fraction"
            index < length(args) ||
                error("--heldout-fraction requires a number")
            heldout_fraction = parse(Float64, args[index + 1])
            index += 2
        elseif arg == "--chains"
            index < length(args) || error("--chains requires an integer")
            chains = parse(Int, args[index + 1])
            index += 2
        elseif arg == "--warmup-per-chain"
            index < length(args) ||
                error("--warmup-per-chain requires an integer")
            warmup_per_chain = parse(Int, args[index + 1])
            index += 2
        elseif arg == "--draws-per-chain"
            index < length(args) ||
                error("--draws-per-chain requires an integer")
            draws_per_chain = parse(Int, args[index + 1])
            index += 2
        elseif arg == "--target-acceptance"
            index < length(args) ||
                error("--target-acceptance requires a number")
            target_acceptance = parse(Float64, args[index + 1])
            index += 2
        elseif arg == "--prior-profile"
            index < length(args) || error("--prior-profile requires a name")
            prior_profile = Symbol(args[index + 1])
            index += 2
        elseif arg == "--progress"
            progress = true
            index += 1
        elseif arg in ("-h", "--help")
            println(usage())
            exit(0)
        else
            error("unknown argument: $arg")
        end
    end

    isfile(remediation_json) ||
        error("sampler remediation artifact not found: $remediation_json")
    max_cells >= 0 || error("--max-cells must be non-negative")
    n_persons >= 6 || error("--n-persons must be at least 6")
    n_raters >= 3 || error("--n-raters must be at least 3")
    0 < heldout_fraction < 0.5 ||
        error("--heldout-fraction must be in (0, 0.5)")
    chains >= 1 || error("--chains must be positive")
    warmup_per_chain >= 0 || error("--warmup-per-chain must be non-negative")
    draws_per_chain >= 1 || error("--draws-per-chain must be positive")
    0 < target_acceptance < 1 ||
        error("--target-acceptance must be in (0, 1)")
    prior_profile in (:default, :tight, :diffuse) ||
        error("--prior-profile must be default, tight, or diffuse")
    return (;
        remediation_json,
        output_json,
        output_md,
        split_offsets,
        max_cells,
        n_persons,
        n_items = size(QMisspec.Q_BASE, 1),
        n_raters,
        heldout_fraction,
        chains,
        warmup_per_chain,
        draws_per_chain,
        target_acceptance,
        prior_profile,
        progress,
    )
end

project_version() =
    String(TOML.parsefile(joinpath(ROOT, "Project.toml"))["version"])
file_sha256(path::AbstractString) = bytes2hex(open(sha256, path))
rel(path::AbstractString) = relpath(path, ROOT)
read_json(path::AbstractString) = JSON3.read(read(path, String))

round3(value) = round(Float64(value); digits = 3)
round4(value) = round(Float64(value); digits = 4)

function keyget(row, name::Symbol, default = missing)
    return name in keys(row) ? getproperty(row, name) : default
end

function finite_float(value)
    ismissing(value) && return missing
    float = Float64(value)
    return isfinite(float) ? float : missing
end

round_or_missing(value, digits::Int = 4) =
    ismissing(finite_float(value)) ? missing : round(finite_float(value);
        digits)

int_or_missing(value) = ismissing(value) ? missing : Int(value)
symbol_or_missing(value) = ismissing(value) ? missing : Symbol(string(value))

function finite_values(values)
    output = Float64[]
    for value in values
        float = finite_float(value)
        ismissing(float) || push!(output, float)
    end
    return output
end

function maximum_or_missing(values)
    finite = finite_values(values)
    isempty(finite) && return missing
    return maximum(finite)
end

function minimum_or_missing(values)
    finite = finite_values(values)
    isempty(finite) && return missing
    return minimum(finite)
end

function selected_cells(remediation, max_cells::Int)
    rows = NamedTuple[]
    for row in remediation.selected_cell_rows
        push!(rows, (;
            scenario = Symbol(string(row.scenario)),
            axis = Symbol(string(row.axis)),
            base_seed = Int(row.base_seed),
            actual_seed = Int(row.actual_seed),
            previous_n_threshold_risk_changes =
                Int(row.previous_n_threshold_risk_changes),
            previous_delta_candidate_log_score =
                Float64(row.previous_delta_candidate_log_score),
            previous_changed_threshold_risks =
                [Symbol(string(value))
                 for value in row.previous_changed_threshold_risks],
        ))
    end
    max_cells == 0 && return rows
    return rows[1:min(max_cells, length(rows))]
end

function scenario_split(options, cell, split_offset::Int)
    scenario = ReplicatedQCategory.scenario_by_name(cell.scenario)
    base_options = merge(options, (; seed = cell.base_seed))
    fitopts = QMisspec.fit_options(base_options, scenario)
    generated = QMisspec.generate_rows(fitopts, scenario)
    split_seed = cell.base_seed + split_offset
    split = SamplerPilot.SplitGrid.controlled_split_rows(
        generated.rows,
        fitopts,
        split_seed,
    )
    return (; scenario, fitopts, generated, split, split_seed)
end

function warning_source(summary)
    symbol_or_missing(keyget(summary, :flag)) === :ok && return :none
    int_or_missing(keyget(summary, :n_failed_direct_constraints, 0)) > 0 &&
        return :direct_constraint
    int_or_missing(keyget(summary, :n_nonfinite_direct_loglikelihood, 0)) > 0 &&
        return :direct_loglikelihood
    int_or_missing(keyget(summary, :n_sampler_warnings, 0)) > 0 &&
        return :sampler_chain
    int_or_missing(keyget(summary, :n_nonfinite_logdensity, 0)) > 0 &&
        return :raw_logdensity
    int_or_missing(keyget(summary, :n_insufficient_chains, 0)) > 0 &&
        return :insufficient_chains
    int_or_missing(keyget(summary, :n_degenerate_parameters, 0)) > 0 &&
        return :degenerate_raw_parameters
    bad_rhat = int_or_missing(keyget(summary, :n_bad_rhat, 0))
    low_ess = int_or_missing(keyget(summary, :n_low_ess, 0))
    bad_rhat > 0 && low_ess > 0 && return :raw_rhat_and_ess
    bad_rhat > 0 && return :raw_rhat
    low_ess > 0 && return :raw_ess
    return :unexplained_by_exported_counts
end

function parameter_issue_counts(parameter_rows, rhat_threshold, ess_threshold)
    n_bad_rhat = count(row -> begin
        rhat = finite_float(keyget(row, :rhat))
        !ismissing(rhat) && rhat > Float64(rhat_threshold)
    end, parameter_rows)
    n_low_ess = count(row -> begin
        ess = finite_float(keyget(row, :ess))
        !ismissing(ess) && ess < Float64(ess_threshold)
    end, parameter_rows)
    n_insufficient = count(row ->
        symbol_or_missing(keyget(row, :flag)) === :insufficient_chains,
        parameter_rows)
    n_degenerate = count(row ->
        symbol_or_missing(keyget(row, :flag)) === :degenerate_draws,
        parameter_rows)
    return (; n_bad_rhat, n_low_ess, n_insufficient, n_degenerate)
end

function fit_context(cell, split_offset::Int, split_seed::Int, scenario,
        fitopts)
    scenario_seed = fitopts.seed + scenario.seed_offset
    return (;
        seed = scenario_seed,
        base_seed = cell.base_seed,
        split_seed,
        split_offset,
        prior_profile = fitopts.prior_profile,
        scenario = scenario.name,
        axis = scenario.axis,
        role = scenario.role,
    )
end

function model_diagnostic_rows(model_spec, scenario, split_context, train_rows,
        full_rows, heldout_indices, fitopts, context)
    started = time_ns()
    train = QMisspec.design_for_rows(train_rows, model_spec, scenario)
    full = QMisspec.design_for_rows(full_rows, model_spec, scenario)
    layout_matches = train.design.parameter_names == full.design.parameter_names
    fit = BayesianMGMFRM.fit(train.spec;
        experimental = true,
        prior = QMisspec.SmallMCMC.source_prior(fitopts.prior_profile),
        backend = :advancedhmc,
        ndraws = fitopts.draws_per_chain,
        warmup = fitopts.warmup_per_chain,
        chains = fitopts.chains,
        seed = fitopts.seed + scenario.seed_offset +
               QMisspec.model_seed_offset(model_spec.model),
        target_accept = fitopts.target_acceptance,
        progress = fitopts.progress,
    )
    elapsed_seconds = (time_ns() - started) / 1e9
    surface = fit.diagnostic_surface
    summary = surface.summary
    direct_counts = parameter_issue_counts(
        keyget(surface, :direct_parameter_rows, NamedTuple[]),
        keyget(summary, :rhat_threshold, 1.01),
        keyget(summary, :ess_threshold, 400.0),
    )
    model_row = merge(context, (;
        model = model_spec.model,
        model_family = fit.design.spec.family,
        fit_succeeded = true,
        returned_type = Symbol(nameof(typeof(fit))),
        layout_matches,
        n_train_observations = length(train_rows),
        n_heldout_observations = length(heldout_indices),
        n_raw_parameters = size(fit.draws, 2),
        n_direct_parameters = size(fit.direct_draws, 2),
        n_draws = size(fit.direct_draws, 1),
        chains = fitopts.chains,
        warmup_per_chain = fitopts.warmup_per_chain,
        draws_per_chain = fitopts.draws_per_chain,
        target_acceptance = fitopts.target_acceptance,
        sampler = fit.sampler,
        backend = fit.backend,
        diagnostic_flag = symbol_or_missing(keyget(summary, :flag)),
        diagnostic_passed = Bool(keyget(summary, :passed, false)),
        warning_source = warning_source(summary),
        max_rhat = round_or_missing(keyget(summary, :max_rhat)),
        min_ess = round_or_missing(keyget(summary, :min_ess)),
        rhat_threshold = round_or_missing(keyget(summary, :rhat_threshold)),
        ess_threshold = round_or_missing(keyget(summary, :ess_threshold)),
        n_bad_rhat = int_or_missing(keyget(summary, :n_bad_rhat)),
        n_low_ess = int_or_missing(keyget(summary, :n_low_ess)),
        n_direct_bad_rhat = direct_counts.n_bad_rhat,
        n_direct_low_ess = direct_counts.n_low_ess,
        n_insufficient_chains =
            int_or_missing(keyget(summary, :n_insufficient_chains)),
        n_direct_insufficient_chains = direct_counts.n_insufficient,
        n_degenerate_parameters =
            int_or_missing(keyget(summary, :n_degenerate_parameters)),
        n_direct_degenerate_parameters = direct_counts.n_degenerate,
        n_block_warnings = int_or_missing(keyget(summary, :n_block_warnings)),
        n_direct_block_warnings =
            int_or_missing(keyget(summary, :n_direct_block_warnings)),
        n_sampler_warnings =
            int_or_missing(keyget(summary, :n_sampler_warnings)),
        n_nonfinite_logdensity =
            int_or_missing(keyget(summary, :n_nonfinite_logdensity)),
        n_nonfinite_direct_loglikelihood =
            int_or_missing(keyget(summary, :n_nonfinite_direct_loglikelihood)),
        n_failed_direct_constraints =
            int_or_missing(keyget(summary, :n_failed_direct_constraints)),
        n_divergences = int_or_missing(keyget(summary, :n_divergences)),
        n_max_treedepth = int_or_missing(keyget(summary, :n_max_treedepth)),
        e_bfmi = round_or_missing(keyget(summary, :e_bfmi)),
        elapsed_seconds = round3(elapsed_seconds),
        public_claim_allowed = false,
    ))
    sampler_rows = [merge(context, (;
        model = model_spec.model,
        chain = Int(row.chain),
        acceptance_rate = round_or_missing(keyget(row, :acceptance_rate)),
        mean_logdensity = round_or_missing(keyget(row, :mean_logdensity)),
        minimum_logdensity =
            round_or_missing(keyget(row, :minimum_logdensity)),
        maximum_logdensity =
            round_or_missing(keyget(row, :maximum_logdensity)),
        n_nonfinite_logdensity =
            int_or_missing(keyget(row, :n_nonfinite_logdensity)),
        n_divergences = int_or_missing(keyget(row, :n_divergences)),
        n_max_treedepth = int_or_missing(keyget(row, :n_max_treedepth)),
        mean_n_steps = round_or_missing(keyget(row, :mean_n_steps)),
        mean_tree_depth = round_or_missing(keyget(row, :mean_tree_depth)),
        max_tree_depth = int_or_missing(keyget(row, :max_tree_depth)),
        mean_step_size = round_or_missing(keyget(row, :mean_step_size)),
        e_bfmi = round_or_missing(keyget(row, :e_bfmi)),
        flag = symbol_or_missing(keyget(row, :flag)),
        public_claim_allowed = false,
    )) for row in surface.sampler_rows]
    block_rows = NamedTuple[]
    for (parameter_space, rows) in
        ((:raw_unconstrained, surface.block_rows),
         (:direct_constrained, surface.direct_block_rows))
        for row in rows
            push!(block_rows, merge(context, (;
                model = model_spec.model,
                parameter_space,
                block = symbol_or_missing(keyget(row, :block)),
                n_parameters = int_or_missing(keyget(row, :n_parameters)),
                max_rhat = round_or_missing(keyget(row, :max_rhat)),
                min_ess = round_or_missing(keyget(row, :min_ess)),
                n_bad_rhat = int_or_missing(keyget(row, :n_bad_rhat)),
                n_low_ess = int_or_missing(keyget(row, :n_low_ess)),
                n_insufficient_chains =
                    int_or_missing(keyget(row, :n_insufficient_chains)),
                n_degenerate_parameters =
                    int_or_missing(keyget(row, :n_degenerate_parameters)),
                flag = symbol_or_missing(keyget(row, :flag)),
                public_claim_allowed = false,
            )))
        end
    end
    return (; model_row, sampler_rows, block_rows, error_row = nothing)
end

function failed_model_diagnostic_row(model_spec, err, cell, split_offset,
        split_seed, scenario, fitopts, train_rows, heldout_indices)
    context = fit_context(cell, split_offset, split_seed, scenario, fitopts)
    row = merge(context, (;
        model = model_spec.model,
        model_family = model_spec.family,
        fit_succeeded = false,
        returned_type = missing,
        layout_matches = false,
        n_train_observations = length(train_rows),
        n_heldout_observations = length(heldout_indices),
        n_raw_parameters = missing,
        n_direct_parameters = missing,
        n_draws = 0,
        chains = fitopts.chains,
        warmup_per_chain = fitopts.warmup_per_chain,
        draws_per_chain = fitopts.draws_per_chain,
        target_acceptance = fitopts.target_acceptance,
        sampler = :nuts,
        backend = :advancedhmc,
        diagnostic_flag = :fit_failed,
        diagnostic_passed = false,
        warning_source = :fit_failed,
        max_rhat = missing,
        min_ess = missing,
        rhat_threshold = missing,
        ess_threshold = missing,
        n_bad_rhat = missing,
        n_low_ess = missing,
        n_direct_bad_rhat = missing,
        n_direct_low_ess = missing,
        n_insufficient_chains = missing,
        n_direct_insufficient_chains = missing,
        n_degenerate_parameters = missing,
        n_direct_degenerate_parameters = missing,
        n_block_warnings = missing,
        n_direct_block_warnings = missing,
        n_sampler_warnings = missing,
        n_nonfinite_logdensity = missing,
        n_nonfinite_direct_loglikelihood = missing,
        n_failed_direct_constraints = missing,
        n_divergences = missing,
        n_max_treedepth = missing,
        e_bfmi = missing,
        elapsed_seconds = missing,
        public_claim_allowed = false,
    ))
    error_row = merge(context, (;
        model = model_spec.model,
        error = sprint(showerror, err),
        public_claim_allowed = false,
    ))
    return (; model_row = row, sampler_rows = NamedTuple[],
        block_rows = NamedTuple[], error_row)
end

function run_cell(options, cell, split_offset::Int)
    split_context = scenario_split(options, cell, split_offset)
    scenario = split_context.scenario
    fitopts = split_context.fitopts
    split = split_context.split
    split_seed = split_context.split_seed
    context = fit_context(cell, split_offset, split_seed, scenario, fitopts)
    model_rows = NamedTuple[]
    sampler_rows = NamedTuple[]
    block_rows = NamedTuple[]
    error_rows = NamedTuple[]
    for spec in QMisspec.MCMC_MODEL_SPECS
        try
            result = model_diagnostic_rows(spec, scenario, split_context,
                split.train_rows, split_context.generated.rows,
                split.heldout_indices, fitopts, context)
            push!(model_rows, result.model_row)
            append!(sampler_rows, result.sampler_rows)
            append!(block_rows, result.block_rows)
        catch err
            result = failed_model_diagnostic_row(spec, err, cell, split_offset,
                split_seed, scenario, fitopts, split.train_rows,
                split.heldout_indices)
            push!(model_rows, result.model_row)
            append!(error_rows, [result.error_row])
        end
    end
    return (; model_rows, sampler_rows, block_rows, error_rows)
end

function warning_source_summary_rows(model_rows)
    sources = sort(unique(row.warning_source for row in model_rows); by = string)
    return [(;
        warning_source = source,
        n_rows = count(row -> row.warning_source === source, model_rows),
        n_models = length(unique(row.model for row in model_rows
            if row.warning_source === source)),
        n_splits = length(unique((row.base_seed, row.scenario,
            row.split_offset) for row in model_rows
            if row.warning_source === source)),
        public_claim_allowed = false,
    ) for source in sources]
end

function model_warning_summary_rows(model_rows)
    models = sort(unique(row.model for row in model_rows); by = string)
    return [(;
        model,
        n_rows = count(row -> row.model === model, model_rows),
        n_warning_rows = count(row -> row.model === model &&
            row.diagnostic_flag !== :ok, model_rows),
        max_rhat = round_or_missing(maximum_or_missing(
            row.max_rhat for row in model_rows if row.model === model)),
        min_ess = round_or_missing(minimum_or_missing(
            row.min_ess for row in model_rows if row.model === model)),
        total_bad_rhat = sum((row.n_bad_rhat for row in model_rows
            if row.model === model && !ismissing(row.n_bad_rhat)); init = 0),
        total_low_ess = sum((row.n_low_ess for row in model_rows
            if row.model === model && !ismissing(row.n_low_ess)); init = 0),
        total_sampler_warnings = sum((row.n_sampler_warnings
            for row in model_rows
            if row.model === model && !ismissing(row.n_sampler_warnings));
            init = 0),
        total_divergences = sum((row.n_divergences for row in model_rows
            if row.model === model && !ismissing(row.n_divergences)); init = 0),
        total_max_treedepth = sum((row.n_max_treedepth for row in model_rows
            if row.model === model && !ismissing(row.n_max_treedepth));
            init = 0),
        public_claim_allowed = false,
    ) for model in models]
end

function remediation_policy_rows()
    return [
        (lever = :warmup,
            current_status = :tested_at_64_per_chain,
            expected_effect =
                :can_help_adaptation_but_not_a_complete_solution_for_low_ess,
            next_action =
                :compare_64_vs_128_warmup_after_exporting_block_diagnostics,
            public_claim_allowed = false),
        (lever = :draws,
            current_status = :tested_at_64_postwarmup_draws_per_chain,
            expected_effect = :directly_increases_effective_sample_size,
            next_action = :increase_draws_before_relaxing_fit_thresholds,
            public_claim_allowed = false),
        (lever = :chains,
            current_status = :tested_at_4_chains,
            expected_effect = :improves_rhat_detection_and_split_stability,
            next_action = :keep_at_least_4_chains_for_gate_diagnostics,
            public_claim_allowed = false),
        (lever = :thinning,
            current_status = :not_exposed_in_current_local_fit_controls,
            expected_effect =
                :usually_reduces_stored_draws_and_does_not_fix_mixing,
            next_action =
                :do_not_use_as_primary_remediation_without_storage_pressure,
            public_claim_allowed = false),
        (lever = :target_acceptance,
            current_status = :tested_at_0_85,
            expected_effect =
                :mainly_addresses_divergence_or_integrator_instability,
            next_action =
                :raise_only_if_sampler_chain_rows_show_geometry_warnings,
            public_claim_allowed = false),
    ]
end

function finding_rows(model_rows, source_summary)
    n_mcmc = count(row -> row.model in MCMC_MODEL_NAMES, model_rows)
    warnings = [row for row in model_rows if row.diagnostic_flag !== :ok]
    raw_ess = count(row -> row.warning_source in
        (:raw_ess, :raw_rhat_and_ess), warnings)
    sampler_geometry = count(row -> row.warning_source in
        (:sampler_chain, :raw_logdensity), warnings)
    return [
        (finding = :warning_surface_diagnosis_recorded,
            severity = :info,
            evidence = string(n_mcmc, " MCMC diagnostic row(s)"),
            implication = :score_rows_now_have_a_diagnostic_followup,
            public_claim_allowed = false),
        (finding = :warnings_persist_after_remediation_budget,
            severity = isempty(warnings) ? :info : :warning,
            evidence = string(length(warnings),
                " MCMC row(s) still have non-ok diagnostic flags"),
            implication =
                :threshold_policy_must_wait_for_sampler_quality_gate,
            public_claim_allowed = false),
        (finding = :low_ess_or_rhat_surface,
            severity = raw_ess == 0 ? :info : :warning,
            evidence = string(raw_ess,
                " warning row(s) are explained by raw R-hat/ESS counts"),
            implication =
                :draws_chains_or_parameterization_are_more_relevant_than_thinning,
            public_claim_allowed = false),
        (finding = :sampler_geometry_surface,
            severity = sampler_geometry == 0 ? :info : :warning,
            evidence = string(sampler_geometry,
                " warning row(s) involve sampler or log-density counts"),
            implication =
                :target_acceptance_or_reparameterization_should_be_checked_if_nonzero,
            public_claim_allowed = false),
        (finding = :public_claims_blocked,
            severity = :blocker,
            evidence = "local warning-surface diagnosis only",
            implication =
                :do_not_claim_public_fit_thresholds_model_weights_or_q_revisions,
            public_claim_allowed = false),
    ]
end

function input_artifact_rows(options)
    return [(artifact = :sampler_remediation_critical_pilot,
        path = rel(options.remediation_json),
        sha256 = file_sha256(options.remediation_json))]
end

function table(io, headers, rows)
    println(io, "| ", join(headers, " | "), " |")
    println(io, "| ", join(fill("---", length(headers)), " | "), " |")
    for row in rows
        println(io, "| ", join(string.(row), " | "), " |")
    end
    println(io)
end

function render_markdown(path, artifact)
    mkpath(dirname(path))
    open(path, "w") do io
        println(io, "# Uto-Style Sampler Warning Surface Diagnosis")
        println(io)
        println(io, "- Generated at: `", artifact.generated_at, "`")
        println(io, "- Local only: `true`")
        println(io, "- Public claims allowed: `false`")
        println(io)
        println(io, "## Interpretation")
        println(io)
        println(io,
            "This report reruns the sampler-remediation critical cells and ",
            "records the diagnostic surface behind `mcmc_warning`. It is meant ",
            "to distinguish sampler geometry, raw R-hat/ESS, direct-transform, ",
            "and budget-related explanations before changing fit thresholds.")
        println(io)
        println(io, "## Findings")
        table(io, ["Finding", "Severity", "Evidence", "Implication"],
            [[row.finding, row.severity, row.evidence, row.implication]
             for row in artifact.finding_rows])
        println(io, "## Warning Sources")
        table(io, ["Source", "Rows", "Models", "Splits"],
            [[row.warning_source, row.n_rows, row.n_models, row.n_splits]
             for row in artifact.warning_source_summary_rows])
        println(io, "## Model Summary")
        table(io, ["Model", "Rows", "Warnings", "Max Rhat", "Min ESS",
                "Bad Rhat", "Low ESS", "Sampler Warnings", "Divergences",
                "Tree Depth"],
            [[row.model, row.n_rows, row.n_warning_rows, row.max_rhat,
                row.min_ess, row.total_bad_rhat, row.total_low_ess,
                row.total_sampler_warnings, row.total_divergences,
                row.total_max_treedepth]
             for row in artifact.model_warning_summary_rows])
        println(io, "## Remediation Levers")
        table(io, ["Lever", "Current", "Expected Effect", "Next Action"],
            [[row.lever, row.current_status, row.expected_effect,
                row.next_action]
             for row in artifact.remediation_policy_rows])
        println(io, "## Boundary")
        println(io)
        println(io,
            "This is local sampler-diagnostic evidence. Threshold profiles, ",
            "model weights, automatic Q revision, and sparse-superiority claims ",
            "remain blocked.")
    end
    return path
end

function build_artifact(options)
    remediation = read_json(options.remediation_json)
    cells = selected_cells(remediation, options.max_cells)
    model_rows = NamedTuple[]
    sampler_rows = NamedTuple[]
    block_rows = NamedTuple[]
    error_rows = NamedTuple[]
    for cell in cells, split_offset in options.split_offsets
        result = run_cell(options, cell, split_offset)
        append!(model_rows, result.model_rows)
        append!(sampler_rows, result.sampler_rows)
        append!(block_rows, result.block_rows)
        append!(error_rows, result.error_rows)
    end
    source_summary = warning_source_summary_rows(model_rows)
    model_summary = model_warning_summary_rows(model_rows)
    remediation_rows = remediation_policy_rows()
    findings = finding_rows(model_rows, source_summary)
    warnings = [row for row in model_rows if row.diagnostic_flag !== :ok]
    return (;
        schema = OUTPUT_SCHEMA,
        family = :mgmfrm,
        scope = :uto_style_sampler_warning_surface_diagnosis,
        status = :local_sampler_warning_surface_recorded,
        generated_at = string(now(UTC)),
        package = (;
            name = "BayesianMGMFRM",
            version = project_version(),
            julia_version = string(VERSION),
        ),
        local_only = true,
        publication_or_registration_action = false,
        public_fit_metric_claim = false,
        public_q_revision_claim = false,
        automatic_q_revision = false,
        public_model_weight_claim = false,
        sparse_mgmfrm_superiority_claim = false,
        input_artifacts = input_artifact_rows(options),
        design = (;
            split_offsets = options.split_offsets,
            n_persons = options.n_persons,
            n_items = options.n_items,
            n_raters = options.n_raters,
            heldout_fraction = options.heldout_fraction,
        ),
        fit_controls = (;
            backend = :advancedhmc,
            sampler = :nuts,
            chains = options.chains,
            warmup_per_chain = options.warmup_per_chain,
            draws_per_chain = options.draws_per_chain,
            target_acceptance = options.target_acceptance,
            prior_profile = options.prior_profile,
            progress = options.progress,
            thinning_available = false,
        ),
        selected_cell_rows = cells,
        model_diagnostic_rows = model_rows,
        sampler_chain_rows = sampler_rows,
        block_diagnostic_rows = block_rows,
        warning_source_summary_rows = source_summary,
        model_warning_summary_rows = model_summary,
        remediation_policy_rows = remediation_rows,
        error_rows,
        finding_rows = findings,
        summary = (;
            passed = isempty(warnings) && isempty(error_rows),
            n_selected_cells = length(cells),
            n_split_offsets = length(options.split_offsets),
            n_model_diagnostic_rows = length(model_rows),
            n_warning_rows = length(warnings),
            n_error_rows = length(error_rows),
            n_sampler_chain_rows = length(sampler_rows),
            n_block_diagnostic_rows = length(block_rows),
            n_raw_rhat_ess_warning_rows =
                count(row -> row.warning_source in
                    (:raw_rhat, :raw_ess, :raw_rhat_and_ess), warnings),
            n_sampler_geometry_warning_rows =
                count(row -> row.warning_source in
                    (:sampler_chain, :raw_logdensity), warnings),
            n_direct_transform_warning_rows =
                count(row -> row.warning_source in
                    (:direct_constraint, :direct_loglikelihood), warnings),
            no_public_fit_metric_claim = true,
            no_public_q_revision_claim = true,
            no_automatic_q_revision = true,
            no_public_model_weight_claim = true,
            no_sparse_superiority_claim = true,
            next_gate = isempty(warnings) ?
                :expand_sampler_remediation_to_split_sensitive_cells :
                :run_block_targeted_budget_and_parameterization_followup,
        ),
    )
end

function main(args = ARGS)
    options = parse_args(args)
    artifact = build_artifact(options)
    write_artifact(options.output_json, artifact)
    render_markdown(options.output_md, artifact)
    println("wrote ", rel(options.output_json))
    println("wrote ", rel(options.output_md))
    println("model_rows=", artifact.summary.n_model_diagnostic_rows,
        " warnings=", artifact.summary.n_warning_rows,
        " raw_rhat_ess_warnings=",
        artifact.summary.n_raw_rhat_ess_warning_rows,
        " sampler_geometry_warnings=",
        artifact.summary.n_sampler_geometry_warning_rows,
        " next_gate=", artifact.summary.next_gate)
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
