module MinimalMFRM
using BayesianMGMFRM

function inputs()
    ratings = (
        examinee = ["E1", "E1", "E1", "E1", "E2", "E2", "E2", "E2"],
        rater = ["R1", "R2", "R1", "R2", "R1", "R2", "R1", "R2"],
        item = ["I1", "I1", "I2", "I2", "I1", "I1", "I2", "I2"],
        score = [0, 1, 2, 0, 1, 2, 0, 2],
    )
    spec = mfrm_spec(ratings; person = :examinee, score = :score,
        facets = (item = :item, rater = :rater), steps = :item,
        category_levels = 0:2, prior = :default)
    validation = validate_design(spec)
    validation.passed || error("Resolve the design validation issues before fitting.")
    return (; spec, validation)
end

function plot_results(fitted, output_dir)
    parameters = [r.parameter for r in posterior_summary(fitted).rows
        if startswith(r.parameter, "rater[")]
    posterior = BayesianMGMFRM.plot(fitted; kind = :posterior, parameters)
    chains = BayesianMGMFRM.plot(fitted; kind = :diagnostics, parameters)
    predictive = BayesianMGMFRM.plot(fitted; kind = :predictive, ndraws = 200, seed = 42)
    for (name, figure) in (("rater-posterior", posterior), ("rater-chains", chains),
            ("category-predictive", predictive)), extension in ("pdf", "svg")
        CairoMakie.save(joinpath(output_dir, "$name.$extension"), figure)
    end
end

"""Run a short standard MFRM example, or reopen a matching trusted fit with `--saved-fit PATH`."""
function main(args = String[]; output_parent = "results/minimal")
    "--cmdstan" in args && throw(ArgumentError(
        "This example uses standard Julia NUTS. For a matching CmdStan model see the Stan adapter guide; the older reference-coded command is examples/legacy/minimal.jl --cmdstan."))
    plots = "--plots" in args
    rest = filter(!=("--plots"), args)
    (count(==("--plots"), args) <= 1 &&
        (isempty(rest) || (length(rest) == 2 && rest[1] == "--saved-fit"))) ||
        throw(ArgumentError("Usage: minimal.jl [--plots] [--saved-fit path/to/fit.jls]"))
    prepared = inputs()
    saved = isempty(rest) ? nothing : load_fit(rest[2])
    if saved !== nothing
        A = BayesianMGMFRM.AdditiveFacets
        saved isa A.Fit && isequal(saved.record.target, A.record(prepared.spec)) ||
            throw(ArgumentError("The saved fit does not match this example's ratings, model and prior."))
    end
    plots && @eval import CairoMakie
    output_dir = mktempdir(mkpath(output_parent); prefix = "nuts-", cleanup = false)
    println("Output directory: ", relpath(output_dir))
    println("The default demonstration uses 50 warmup + 50 retained draws per chain; not sufficient for inference.")
    fitted = saved === nothing ? fit(prepared.spec; ndraws = 50, warmup = 50,
        chains = 2, seed = 102, progress = false) : saved
    cache = joinpath(output_dir, "fit.jls")
    save_fit(cache, fitted)
    println("Saved fit: ", relpath(cache))
    flush(stdout)
    H = BayesianMGMFRM.PortableHandoff
    handoff = H.export_handoff(fitted)
    handoff_path = joinpath(output_dir, "handoff.json")
    H.save_handoff(handoff_path, handoff)
    H.load_handoff(handoff_path).record.handoff_bundle_sha256 ==
        handoff.record.handoff_bundle_sha256 || error("Portable handoff checksum mismatch.")
    restored = load_fit(cache)
    isequal(posterior_summary(restored), posterior_summary(fitted)) ||
        error("Saved and reloaded posterior summaries differ.")
    q = qualify(restored)
    println("Numerical qualification: ", q.qualified, "; max R-hat: ", q.max_rhat,
        "; min bulk/tail ESS: ", q.min_bulk_ess, " / ", q.min_tail_ess)
    q.qualified || println("Inspect diagnostics(fitted) before interpreting estimates.")
    show(stdout, MIME"text/plain"(), posterior_summary(restored).rows)
    println()
    plots && Base.invokelatest(plot_results, restored, output_dir)
    return (; directory = output_dir, fitted = restored, qualification = q)
end
end

if abspath(PROGRAM_FILE) == @__FILE__
    MinimalMFRM.main(ARGS)
end
