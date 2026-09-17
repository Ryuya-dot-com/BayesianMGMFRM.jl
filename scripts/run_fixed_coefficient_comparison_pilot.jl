#!/usr/bin/env julia
# One C2 pilot dataset, two primary fits; no evaluation grid or automatic retry.
# Run prepare, advancedhmc, cmdstan, compare as separate bounded processes.
using BayesianMGMFRM, Random, Serialization, SHA, Statistics, Dates
include(joinpath(@__DIR__, "mfrm_validation_preparation.jl"))
const B = BayesianMGMFRM
const E = B.Experimental
const V = MFRMValidationPreparation
const REPO = dirname(@__DIR__)
const CONTROLS = (; chains=4, warmup=1000, ndraws=1000, step_size=0.03,
    target_accept=0.9, max_depth=10, metric=:diagonal, init_jitter=0.1,
    record_warmup=true, progress=false)
const CRITERIA = (; chains=4, rhat=1.01, ess=400., ebfmi=0.3, allow_treedepth_hits=false)
const SEEDS = (; persons=2026091801, responses=2026091802,
    advancedhmc=2026091803, cmdstan=2026091804)
digest(path) = bytes2hex(sha256(read(path)))
writejson(path, value) = B._write_json_record(path, value)

function source_hashes()
    paths = [joinpath(d, f) for (d, _, fs) in walkdir(joinpath(REPO, "src")) for f in fs]
    append!(paths, [@__FILE__, joinpath(@__DIR__, "mfrm_validation_preparation.jl")])
    return Dict(relpath(p, REPO) => digest(p) for p in paths)
end

function prepare(root)
    ispath(root) && error("Use a new pilot directory; existing attempts must be preserved")
    mkpath(root)
    panel = V.recovery_panel(MersenneTwister(SEEDS.persons), MersenneTwister(SEEDS.responses);
        persons=48, rho=0.6)
    serialize(joinpath(root, "panel.jls"), panel) # Preserve before model validation.
    writejson(joinpath(root, "panel.json"), (; truth=panel.truth, data=panel.data))
    spec = V.specification(panel)
    @assert spec.data.n == 1536
    model = E.correlated(spec; lkj_eta=2)
    prior = E.ExchangeablePrior(person_sd=1., item_sd=1., step_sd=0.5, rater_kernel_sd=0.5)
    target = B._fixed_q_prior_target(model, prior)
    initial = B.initial_params(target)
    @assert all(iszero, initial) # No truth-informed initialization.
    declaration = (; phase=:cost_and_computation_pilot, case="C2", dataset_id="pilot-only-1",
        created_at=string(now(UTC)), source_revision=strip(read(`git -C $REPO rev-parse HEAD`, String)),
        source_hashes=source_hashes(), environment=B._evidence_project_hashes(; include_paths=true),
        julia_version=string(VERSION), seeds=SEEDS, controls=CONTROLS, criteria=CRITERIA,
        target_identity=V.target_identity(target), panel_sha256=digest(joinpath(root, "panel.jls")),
        rng="MersenneTwister generation and host sampling; distinct component/backend seeds",
        julia_chain_rng="One host stream sequentially consumed by initialization and sampling across chains",
        cmdstan_chain_rng="Host draws distinct UInt32 chain seeds before jitter; Stan samples externally",
        initial, prior, lkj_eta=2, planned_calls=2, automatic_retries=false,
        wall_seconds_per_process=1800, rss_stop_bytes=8*1024^3, output_stop_bytes=5*1024^3,
        resource_policy="External deadline; operator observes process-tree RSS/output every <=60 s and interrupts on excess. Not hard memory/storage containment.",
        comparison_policy="30 statistics, within-pair alpha=.05; .1 pooled posterior SD, capped at .02 for rho and .01 for probability",
        scientific_acceptance=false, evaluation_replications=0)
    serialize(joinpath(root, "declaration.jls"), declaration)
    writejson(joinpath(root, "declaration.json"), declaration)
    println("Prepared ", declaration.target_identity, "; dimension=", length(initial))
end

function inputs(root)
    declaration = deserialize(joinpath(root, "declaration.jls"))
    @assert declaration.source_hashes == source_hashes()
    @assert declaration.environment == B._evidence_project_hashes(; include_paths=true)
    @assert declaration.julia_version == string(VERSION)
    @assert declaration.panel_sha256 == digest(joinpath(root, "panel.jls"))
    panel = deserialize(joinpath(root, "panel.jls"))
    model = E.correlated(V.specification(panel); lkj_eta=declaration.lkj_eta)
    @assert V.target_identity(B._fixed_q_prior_target(model, declaration.prior)) == declaration.target_identity
    return declaration, panel, model
end

function fit_one(root, backend)
    declaration, panel, model = inputs(root)
    directory = joinpath(root, string(backend))
    ispath(directory) && error("Existing primary attempt must not be overwritten")
    mkpath(directory)
    writejson(joinpath(directory, "started.json"), (; pid=getpid(), started_at=string(now(UTC)),
        backend, seed=getproperty(declaration.seeds, backend), declaration_sha256=digest(joinpath(root,"declaration.jls"))))
    println("Starting ", backend, " pid=", getpid()); flush(stdout)
    started = time()
    try
        extra = backend === :cmdstan ? (; cmdstan_cache_dir=joinpath(directory, "compile")) : (;)
        fit = E.fit(model; prior=declaration.prior, backend, init=declaration.initial,
            seed=getproperty(declaration.seeds, backend), declaration.controls..., extra...)
        fit_seconds = time()-started
        cache = joinpath(directory, "fit.jls")
        save_fit_cache(cache, fit; artifact_include_draws=true, artifact_include_sampler_stats=true)
        restored = load_fit_cache(cache)
        @assert isequal(fit_metadata(fit), fit_metadata(restored))
        @assert isequal(diagnostics(fit), diagnostics(restored))
        @assert isequal(B.direct_posterior_summary(fit), B.direct_posterior_summary(restored))
        writejson(joinpath(directory, "result.json"), (; status=:completed, backend, fit_seconds,
            julia_process_peak_rss_bytes=Sys.maxrss(), controls=fit.record.run.controls,
            diagnostics=diagnostics(restored), target_identity=fit.record.target_identity,
            cache_sha256=digest(cache), scientific_acceptance=false))
        println("Completed ", backend, " in ", fit_seconds, " seconds; ", diagnostics(restored).summary)
    catch err
        writejson(joinpath(directory, "failure.json"), (; status=:fit_or_persistence_error,
            backend, elapsed_seconds=time()-started, error=sprint(showerror, err)))
        rethrow()
    end
end

function compare(root)
    declaration, panel, _ = inputs(root)
    output = joinpath(root, "comparison.json")
    ispath(output) && error("Comparison already exists")
    fits = map((:advancedhmc, :cmdstan)) do backend
        fit = load_fit_cache(joinpath(root, string(backend), "fit.jls"))
        V.prepare_comparison_fit(panel, fit; expected_target_identity=declaration.target_identity,
            criteria=declaration.criteria)
    end
    margins = [begin
        @assert a.parameter == b.parameter
        cap = a.parameter == "rho" ? 0.02 : a.parameter == "mean_Pr(Y>=2)" ? 0.01 : Inf
        (; parameter=a.parameter, tolerance=min(cap, 0.1sqrt((a.posterior_sd^2+b.posterior_sd^2)/2)))
    end for (a,b) in zip(fits[1].rows, fits[2].rows)]
    plan = [(; id="C2-pilot-only-1", declaration.target_identity, margins)]
    comparison = V.compare_backend_pairs(plan,
        [(; id=only(plan).id, declaration.target_identity,
            result=(; julia=fits[1], cmdstan=fits[2]))]; alpha=0.05, independent_streams=true)
    @assert comparison.planned_statistics == 30
    writejson(output, (; declaration_sha256=digest(joinpath(root,"declaration.jls")), fits, comparison,
        evaluation_replications=0, scientific_acceptance=false))
    println(comparison.statistic_counts)
end

function main(args)
    length(args) == 2 || error("Usage: script.jl prepare|advancedhmc|cmdstan|compare OUTPUT_DIRECTORY")
    action, root = args[1], abspath(args[2])
    action in ("prepare", "advancedhmc", "cmdstan", "compare") || error("Unknown action")
    action == "prepare" ? prepare(root) : action == "compare" ? compare(root) : fit_one(root, Symbol(action))
end
abspath(PROGRAM_FILE) == (@__FILE__) && main(ARGS)
