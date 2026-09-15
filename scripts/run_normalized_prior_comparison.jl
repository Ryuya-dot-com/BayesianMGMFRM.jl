module NormalizedPriorComparison

using BayesianMGMFRM, Dates, SHA, Statistics, Serialization
const B = BayesianMGMFRM
include("run_cmdstan_backend_validation.jl")

# Two predeclared budgets for one fixed experiment. No automatic retry.
const CONTROLS = (; ndraws = 1500, warmup = 1000, chains = 4,
    step_size = 0.03, target_accept = 0.9, max_depth = 10,
    metric = :diagonal, init_jitter = 0.25)
const SCALES = (; person_sd = 0.7, rater_sd = 0.4, item_sd = 0.6,
    log_discrimination_sd = 0.3, log_consistency_sd = 0.35, step_sd = 0.5)
const GATE = (; rhat = 1.01, ess = 400.0, ebfmi = 0.3,
    mcse_sd_ratio = 0.05, combined_mcse_multiplier = 4.5,
    difference_bound_sd_ratio = 0.3)
const PROBABILITIES = (0.1, 0.5, 0.9)
const SEEDS = ((9173101, 9173102), (9173201, 9173202))
const PRECISION_CONTROLS = merge(CONTROLS, (; ndraws = 6000))
const PRECISION_SEEDS = ((9174101, 9174102), (9174201, 9174202))
const CONTRASTS = ["ability[P1-P2,dim1]", "ability[P1-P2,dim2]",
    "severity[R2-R1]", "log_consistency[R2/R1]", "difficulty[I1-I2]",
    "loading[I1,dim1-I2,dim1]"]

function targets()
    case = CmdStanBackendValidation.simulated_case(:mgmfrm, :dense;
        seed = 9173001, truth_scale = 0.15)
    return [B._MGMFRMNormalizedPriorLogDensity(case.spec;
        prior_model = model, scales = SCALES,
        source_rater = model === :source ? "R2" : nothing)
        for model in (:exchangeable, :source)]
end

function comparison_input(target, result)
    result.record.target_identity == B._mgmfrm_normalized_prior_identity(target) ||
        throw(ArgumentError("comparison target mismatch"))
    direct = result.diagnostics.direct_values.direct_draws
    blocks = target.base.design.blocks
    person, rater, consistency, item, loading =
        [blocks[name] for name in (:person, :rater, :rater_consistency,
            :item, :item_dimension_discrimination)]
    contrasts = hcat(direct[:, person[1]] - direct[:, person[3]],
        direct[:, person[2]] - direct[:, person[4]],
        direct[:, rater[2]] - direct[:, rater[1]],
        log.(direct[:, consistency[2]]) - log.(direct[:, consistency[1]]),
        direct[:, item[1]] - direct[:, item[2]],
        direct[:, loading[1]] - direct[:, loading[2]])
    return (;
        draws = hcat(result.record.run.draws, direct, contrasts),
        names = vcat("raw:" .* result.raw_parameter_names,
            "direct:" .* result.direct_parameter_names, "contrast:" .* CONTRASTS),
    )
end

function summarize(draws, names, chains)
    diagnostic = B._candidate_mcmc_diagnostic_rows(draws, names, chains;
        split_chains = true, rhat_threshold = GATE.rhat, ess_threshold = GATE.ess)
    mcse = B._posterior_mcse_rows(draws, names, chains;
        probabilities = PROBABILITIES, parameter_space = :comparison)
    return [begin
        values = view(draws, :, i)
        d, m = diagnostic[i], mcse[i]
        summaries = ((; statistic = :mean, estimate = mean(values), mcse = m.mean_mcse),
            (; statistic = :sd, estimate = std(values), mcse = m.sd_mcse),
            ((; statistic = Symbol("q", q.probability), q.estimate, q.mcse) for q in m.quantiles)...)
        (; parameter = names[i], posterior_sd = std(values),
            rhat = d.rank_normalized_rhat, bulk_ess = d.bulk_ess, tail_ess = d.tail_ess,
            diagnostic_passed = d.flag === :ok && isfinite(d.rank_normalized_rhat) &&
                d.rank_normalized_rhat < GATE.rhat && d.bulk_ess >= GATE.ess && d.tail_ess >= GATE.ess,
            mcse_status = m.mcse_status, summaries)
    end for i in axes(draws, 2)]
end

function fit_diagnostics(result, parameters)
    rows = result.record.run.sampler_rows
    divergences = sum(r.n_divergences for r in rows)
    depth_hits = sum(r.n_max_treedepth for r in rows)
    energies = [r.e_bfmi for r in rows]
    passed = all(r -> r.diagnostic_passed, parameters) &&
        divergences == 0 && depth_hits == 0 &&
        all(x -> !ismissing(x) && isfinite(x) && x >= GATE.ebfmi, energies) &&
        result.diagnostics.n_failed_direct_constraints == 0 &&
        result.diagnostics.n_nonfinite_direct_loglikelihood == 0
    return (; passed, divergences, depth_hits, ebfmi = energies,
        max_rhat = maximum(r.rhat for r in parameters),
        min_bulk_ess = minimum(r.bulk_ess for r in parameters),
        min_tail_ess = minimum(r.tail_ess for r in parameters))
end

function compare(left, right; diagnostic_passed::Bool)
    !isempty(left) && length(left) == length(right) &&
        [r.parameter for r in left] == [r.parameter for r in right] ||
        throw(ArgumentError("comparison parameters do not match"))
    rows = NamedTuple[]
    for (a, b) in zip(left, right)
        length(a.summaries) == length(b.summaries) || throw(ArgumentError("summary count mismatch"))
        pooled_sd = hypot(a.posterior_sd, b.posterior_sd) / sqrt(2)
        for (x, y) in zip(a.summaries, b.summaries)
            x.statistic === y.statistic || throw(ArgumentError("comparison statistics do not match"))
            available = !ismissing(x.mcse) && !ismissing(y.mcse) &&
                all(isfinite, (x.estimate, y.estimate, x.mcse, y.mcse, pooled_sd)) &&
                x.mcse > 0 && y.mcse > 0 && pooled_sd > 0
            difference = y.estimate - x.estimate
            combined = available ? hypot(x.mcse, y.mcse) : missing
            z = available ? abs(difference) / combined : missing
            upper_ratio = available ? (abs(difference) + GATE.combined_mcse_multiplier * combined) / pooled_sd : missing
            precision_passed = available && max(x.mcse, y.mcse) / pooled_sd <= GATE.mcse_sd_ratio
            compatible = available && z <= GATE.combined_mcse_multiplier
            within_resolution = available && upper_ratio <= GATE.difference_bound_sd_ratio
            status = !diagnostic_passed || !a.diagnostic_passed || !b.diagnostic_passed ? :diagnostic_hold :
                !available ? :mcse_unavailable : !precision_passed ? :precision_hold :
                !compatible ? :backend_difference : !within_resolution ? :resolution_hold : :within_resolution
            push!(rows, (; parameter = a.parameter, statistic = x.statistic,
                julia_estimate = x.estimate, cmdstan_estimate = y.estimate,
                julia_mcse = x.mcse, cmdstan_mcse = y.mcse, difference,
                pooled_sd, combined_mcse = combined, absolute_mcse_z = z,
                difference_bound_sd_ratio = upper_ratio, precision_passed,
                compatible, within_resolution, status))
        end
    end
    return rows
end

function source_hashes()
    root = dirname(@__DIR__)
    paths = [joinpath("src", relpath(joinpath(dir, file), joinpath(root, "src")))
        for (dir, _, files) in walkdir(joinpath(root, "src")) for file in files
        if endswith(file, ".jl") || endswith(file, ".stan")]
    append!(paths, ["Project.toml", "Manifest.toml",
        "scripts/run_normalized_prior_comparison.jl", "scripts/run_cmdstan_backend_validation.jl"])
    return [(; path, sha256 = bytes2hex(sha256(read(joinpath(root, path))))) for path in sort(paths)]
end

function precision_reference(cases)
    directory = joinpath("results", "normalized-prior-comparison", "20260913-fixed-q-01")
    expected = (
        "protocol.json" => "d7e87955feb1c54cf8cfd927ff81aca896c00e13ca9657d395c564169e8f9498",
        "protocol.jls" => "06c2a915f8a5415867ad71d0fd9e5365ece777ada6aa4cf8c87e27eed4638533",
        "comparison.json" => "2d697a0367f2310661a70d47dcd0787f87e2909a4bc257860cf2f218c7e25ed2")
    files = map(expected) do (name, sha)
        path = joinpath(directory, name)
        bytes2hex(sha256(read(joinpath(dirname(@__DIR__), path)))) == sha ||
            error("initial comparison receipt changed: $path")
        (; path, sha256 = sha)
    end
    original = open(deserialize, joinpath(dirname(@__DIR__), directory, "protocol.jls"))
    @assert original.controls == CONTROLS && original.gate == GATE && original.scales == SCALES
    @assert original.probabilities == PROBABILITIES && original.contrasts == CONTRASTS
    @assert [t.identity for t in original.targets] == B._mgmfrm_normalized_prior_identity.(cases)
    return (; relation = :precision_followup_same_data, files,
        protocol_hash = B._cache_hash(original), initial_status = :unresolved,
        combine_draws = false)
end

function run(output::AbstractString; precision_followup::Bool = false)
    ispath(output) && throw(ArgumentError("comparison output must be a new directory"))
    cases = targets()
    controls = precision_followup ? PRECISION_CONTROLS : CONTROLS
    seeds = precision_followup ? PRECISION_SEEDS : SEEDS
    previous = precision_followup ? precision_reference(cases) : nothing
    protocol = (; schema = "bayesianmgmfrm.normalized_prior_comparison.v1",
        created_utc = string(now(UTC)), julia_version = string(VERSION),
        controls, scales = SCALES, gate = GATE, probabilities = PROBABILITIES,
        simulation_seed = 9173001, truth_scale = 0.15, fit_seeds = seeds,
        contrasts = CONTRASTS, comparison_direction = :cmdstan_minus_julia,
        retries = 0, max_fits = 4,
        scope = :single_fixed_q_dataset_not_recovery_or_general_equivalence,
        targets = [(; identity = B._mgmfrm_normalized_prior_identity(t),
            prior = B._mgmfrm_normalized_prior_record(t),
            design = B._design_identity_payload(t.base.design)) for t in cases],
        source_hashes = source_hashes())
    precision_followup && (protocol = merge(protocol, (; previous)))
    mkpath(output)
    # Publish the exact plan before the first sampler call, and retain it on failure.
    B._save_serialized_record(joinpath(output, "protocol.jls"), protocol)
    B._write_json_record(joinpath(output, "protocol.json"), protocol)
    protocol_hash = B._cache_hash(protocol)
    println("Protocol frozen: ", protocol_hash)
    flush(stdout)
    pairs = NamedTuple[]
    for (p, target) in enumerate(cases)
        fits = NamedTuple[]
        for (b, backend) in enumerate((:advancedhmc, :cmdstan))
            label = "$(target.prior_model)-$backend"
            println("Starting ", label, " at ", now(UTC)); flush(stdout)
            started = time_ns()
            options = backend === :cmdstan ? (; cmdstan_cache_dir = joinpath(output, "compile-$label")) : (;)
            result = B._mgmfrm_normalized_prior_sample(target; backend,
                controls..., seed = seeds[p][b], options...)
            elapsed_seconds = (time_ns() - started) / 1e9
            path = joinpath(output, "$label.jls")
            B._save_mgmfrm_normalized_prior_samples(path, result)
            loaded = B._load_mgmfrm_normalized_prior_samples(path;
                expected_identity = B._mgmfrm_normalized_prior_identity(target))
            isequal(loaded.record.run, result.record.run) || error("saved run changed")
            @assert all(name -> getproperty(loaded.record.run.controls, name) ==
                getproperty(controls, name), keys(controls))
            @assert loaded.record.run.controls.rng.seed == seeds[p][b]
            input = comparison_input(target, loaded)
            length(input.names) == 64 || error("fixed comparison quantity count changed")
            parameters = summarize(input.draws, input.names, controls.chains)
            diagnostic = fit_diagnostics(loaded, parameters)
            fit = (; backend, seed = seeds[p][b], elapsed_seconds, diagnostic, parameters,
                sample_file = basename(path), sample_content_hash = loaded.record.content_hash,
                sample_file_sha256 = bytes2hex(sha256(read(path))),
                sampler_controls = loaded.record.run.controls,
                sampler_rows = loaded.record.run.sampler_rows)
            B._write_json_record(joinpath(output, "$label-summary.json"), fit)
            push!(fits, fit)
            println("Finished ", label, ": ", diagnostic); flush(stdout)
        end
        rows = compare(fits[1].parameters, fits[2].parameters;
            diagnostic_passed = all(f -> f.diagnostic.passed, fits))
        length(rows) == 320 || error("fixed comparison statistic count changed")
        pair = (; prior_model = target.prior_model,
            target_identity = B._mgmfrm_normalized_prior_identity(target), fits,
            status = all(r -> r.status === :within_resolution, rows) ? :within_resolution : :unresolved,
            rows)
        B._write_json_record(joinpath(output, "$(target.prior_model)-comparison.json"), pair)
        push!(pairs, pair)
    end
    source_hashes() == protocol.source_hashes || error("source changed during comparison")
    report = (; schema = protocol.schema, protocol_hash,
        status = all(p -> p.status === :within_resolution, pairs) ? :within_resolution : :unresolved,
        scope = protocol.scope, pairs)
    B._write_json_record(joinpath(output, "comparison.json"), report)
    println("Comparison completed: ", report.status)
    return report
end

end

if abspath(PROGRAM_FILE) == @__FILE__
    length(ARGS) in (1, 2) && (length(ARGS) == 1 || ARGS[2] == "--precision-followup") ||
        error("usage: julia --project=. scripts/run_normalized_prior_comparison.jl NEW_OUTPUT_DIRECTORY [--precision-followup]")
    NormalizedPriorComparison.run(ARGS[1]; precision_followup = length(ARGS) == 2)
end
