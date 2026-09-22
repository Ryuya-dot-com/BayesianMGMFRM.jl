#!/usr/bin/env julia
# One Julia follow-up of a preserved C2 panel; run under measure_command.py.
# Only the explicitly selected metric may change; no retry or new dataset.
include(joinpath(@__DIR__, "run_fixed_coefficient_comparison_pilot.jl"))

function followup(pilot, root; metric=:diagonal, wall_seconds::Int=1800)
    metric in (:diagonal, :dense) || error("Follow-up metric must be diagonal or dense")
    0 < wall_seconds <= 3600 || error("Follow-up wall time must be between 1 and 3600 seconds")
    ispath(root) && error("Use a new output directory; preserve previous attempts")
    original = deserialize(joinpath(pilot, "declaration.jls"))
    panel_path = joinpath(pilot, "panel.jls")
    @assert digest(panel_path) == original.panel_sha256
    @assert original.julia_version == string(VERSION)
    @assert original.environment == B._evidence_project_hashes(; include_paths=true)
    panel = deserialize(panel_path)
    model = E.correlated(V.specification(panel); lkj_eta=original.lkj_eta)
    @assert V.target_identity(B._fixed_q_prior_target(model, original.prior)) == original.target_identity
    @assert original.controls == CONTROLS && original.criteria == CRITERIA
    controls = merge(original.controls, (; metric))
    hashes = merge(source_hashes(), Dict(relpath(@__FILE__, REPO) => digest(@__FILE__)))
    report_options = (; view=:public, include_prior_predictive=true,
        prior_predictive_ndraws=200, ndraws=100, seed=2026091805, require_complete=true)
    mkpath(root)
    cp(panel_path, joinpath(root, "panel.jls"))
    cp(@__FILE__, joinpath(root, "producer-recipe.jl"))
    declaration = (; phase=:julia_computation_followup, original_pilot=abspath(pilot),
        original_declaration_sha256=digest(joinpath(pilot, "declaration.jls")),
        source_revision=strip(read(`git -C $REPO rev-parse HEAD`, String)),
        source_hashes=hashes, environment=original.environment,
        julia_version=string(VERSION), original.panel_sha256, original.target_identity,
        original.prior, original.initial, original.lkj_eta, controls, original.criteria,
        original_controls=original.controls,
        comparison_policy="Only metric may differ. Retain the original whole-fit gate; additionally inspect finite-panel person/item means and their location-invariant contrasts. One panel cannot select a default or establish scientific acceptance.",
        backend=:advancedhmc, seed=original.seeds.advancedhmc, report_options,
        planned_calls=1, automatic_retries=false, wall_seconds_per_process=wall_seconds,
        rss_stop_bytes=8*1024^3, output_stop_bytes=5*1024^3,
        resource_policy="External deadline; observe process RSS/output every <=60 s; interrupt on excess. Not hard memory/storage containment.",
        timing_policy="First public calls in one fresh process; invokelatest includes operation compilation. Earlier phases can warm later phases. Report is structured data, without figure rendering.",
        scientific_acceptance=false, evaluation_replications=0)
    serialize(joinpath(root, "declaration.jls"), declaration)
    writejson(joinpath(root, "declaration.json"), declaration)
    writejson(joinpath(root, "started.json"), (; pid=getpid(), started_at=string(now(UTC))))
    timings = NamedTuple[]
    # This is only a phase timer; the existing external helper owns the deadline.
    function measured(f, label, args...; kwargs...)
        writejson(joinpath(root, "current-phase.json"), (; phase=label, status=:started))
        println("Starting ", label); flush(stdout)
        started = time_ns()
        try
            value = Base.invokelatest(f, args...; kwargs...)
            push!(timings, (; phase=label, seconds=(time_ns()-started)/1e9,
                process_peak_rss_bytes=Sys.maxrss()))
            writejson(joinpath(root, "timings.json"), timings)
            println("Completed ", label, " in ", last(timings).seconds, " seconds"); flush(stdout)
            return value
        catch err
            writejson(joinpath(root, "failure.json"), (; phase=label,
                seconds=(time_ns()-started)/1e9, error=sprint(showerror,err)))
            rethrow()
        end
    end
    fit = measured(E.fit, :fit, model; prior=declaration.prior,
        backend=declaration.backend, init=declaration.initial,
        seed=declaration.seed, declaration.controls...)
    cache = joinpath(root, "fit.jls")
    measured(save_fit_cache, :save, cache, fit;
        artifact_include_draws=true, artifact_include_sampler_stats=true)
    restored = measured(load_fit_cache, :reload, cache)
    writejson(joinpath(root, "current-phase.json"), (; phase=:roundtrip_check, status=:started))
    # Specification objects contain copied arrays and have no value equality.
    # The canonical hash covers their semantics; compare numerical samples too.
    @assert fit.record.content_hash == restored.record.content_hash
    @assert isequal(fit.record.run, restored.record.run)
    report = measured(fit_report, :report, restored; report_options...)
    writejson(joinpath(root, "report.json"), report)
    comparison = measured(V.prepare_comparison_fit, :diagnostic_qualification, panel, restored;
        expected_target_identity=declaration.target_identity, criteria=declaration.criteria)
    writejson(joinpath(root, "qualification.json"), comparison)
    @assert hashes == merge(source_hashes(), Dict(relpath(@__FILE__, REPO) => digest(@__FILE__)))
    writejson(joinpath(root, "result.json"), (; status=:completed, timings,
        target_identity=restored.record.target_identity, cache_sha256=digest(cache),
        exact_sample_roundtrip=true, qualification=comparison.qualification,
        scientific_acceptance=false, evaluation_replications=0))
    writejson(joinpath(root, "current-phase.json"), (; phase=:complete, status=:completed))
end

if abspath(PROGRAM_FILE) == (@__FILE__)
    length(ARGS) in (2, 3, 4) || error("Usage: script.jl ORIGINAL_PILOT NEW_OUTPUT_DIRECTORY [diagonal|dense] [WALL_SECONDS <= 3600]")
    followup(abspath(ARGS[1]), abspath(ARGS[2]);
        metric=length(ARGS) >= 3 ? Symbol(ARGS[3]) : :diagonal,
        wall_seconds=length(ARGS) == 4 ? parse(Int, ARGS[4]) : 1800)
end
