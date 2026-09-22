#!/usr/bin/env julia
# One cost probe, not posterior qualification. Use measure_command.py externally.
include(joinpath(@__DIR__, "run_fixed_coefficient_comparison_pilot.jl"))
using Profile, LinearAlgebra

cost_clock() = (; wall=time_ns(), compile=first(Base.cumulative_compile_time_ns()), gc=Base.gc_time_ns())
cost_delta(a, b) = (; seconds=(b.wall-a.wall)/1e9,
    compile_seconds=(b.compile-a.compile)/1e9, gc_seconds=(b.gc-a.gc)/1e9)

function sampling_cost(pilot, root, metric)
    metric in (:diagonal, :dense) || error("metric must be diagonal or dense")
    ispath(root) && error("Use a new output directory; preserve every attempt")
    original = deserialize(joinpath(pilot, "declaration.jls"))
    panel_path = joinpath(pilot, "panel.jls")
    @assert digest(panel_path) == original.panel_sha256
    @assert original.julia_version == string(VERSION)
    @assert original.environment == B._evidence_project_hashes(; include_paths=true)
    @assert original.controls == CONTROLS && original.criteria == CRITERIA
    panel = deserialize(panel_path)
    model = E.correlated(V.specification(panel); lkj_eta=original.lkj_eta)
    @assert V.target_identity(B._fixed_q_prior_target(model, original.prior)) == original.target_identity
    controls = merge(original.controls, (; metric, chains=1, ndraws=100))
    hashes = merge(source_hashes(), Dict(relpath(@__FILE__, REPO)=>digest(@__FILE__)))
    mkpath(root)
    cp(@__FILE__, joinpath(root, "producer-recipe.jl"))
    declaration = (; phase=:sampling_cost_probe, original_pilot=abspath(pilot),
        original_declaration_sha256=digest(joinpath(pilot,"declaration.jls")),
        source_revision=strip(read(`git -C $REPO rev-parse HEAD`, String)),
        source_hashes=hashes, environment=original.environment, julia_version=string(VERSION),
        threads=Threads.nthreads(), blas_threads=BLAS.get_num_threads(),
        original.panel_sha256, original.target_identity, original.prior, original.initial,
        original.lkj_eta, original_controls=original.controls, controls,
        original_criteria=original.criteria, seed=original.seeds.advancedhmc,
        planned_calls=1, automatic_retries=false, wall_seconds_per_process=1200,
        rss_stop_bytes=8*1024^3, output_stop_bytes=5*1024^3,
        resource_policy="External deadline; observe owned RSS/output every <=60 s. Not hard memory/storage containment.",
        scope="Same panel/target/prior/initial/seed; only metric, chains=1 and retained draws=100 differ. Warmup remains 1000. Not a qualification run or a historical fit-time reconstruction.",
        timing_policy="Fresh process; default compilation; Profile sampling every 0.01 s. Per-phase compilation/GC are included in elapsed time, not additive stages. First transition includes sample initialization and compilation. Observer work is separate. Host is uncontrolled; no repeated benchmark.",
        scientific_acceptance=false, evaluation_replications=0)
    writejson(joinpath(root,"declaration.json"), declaration)
    writejson(joinpath(root,"started.json"), (; pid=getpid(), started_at=string(now(UTC))))
    phases, transitions = NamedTuple[], NamedTuple[]
    previous = Ref(cost_clock())
    observer_seconds = Ref(0.0)
    Profile.init(n=10_000_000, delay=0.01)
    Profile.clear()
    open(joinpath(root,"transitions.tsv"), "w") do io
        println(io, "chain\titeration\tphase\tseconds\tcompile_seconds\tgc_seconds\tn_steps\ttree_depth\tdivergent\tstep_size")
        flush(io)
        observer = function(event)
            entered = cost_clock()
            elapsed = cost_delta(previous[], entered)
            if event.phase === :transition
                s = event.stat
                row = (; chain=event.chain, iteration=s.iterations,
                    phase=s.is_adapt ? :warmup : :retained, elapsed...,
                    n_steps=s.n_steps, tree_depth=s.tree_depth,
                    divergent=s.numerical_error, step_size=s.step_size)
                push!(transitions, row)
                println(io, join(values(row), '\t'))
                if s.iterations % 25 == 0
                    flush(io)
                    println("Iteration ", s.iterations, "/", controls.warmup+controls.ndraws,
                        " phase=", row.phase, " n_steps=", row.n_steps)
                    flush(stdout)
                end
            else
                push!(phases, (; phase=event.phase === :sampling_start ? :setup : :sampling_tail,
                    elapsed...))
                writejson(joinpath(root,"phases.json"), phases)
                flush(io)
            end
            previous[] = cost_clock()
            observer_seconds[] += (previous[].wall-entered.wall)/1e9
            return nothing
        end
        measured = Profile.@profile @timed begin
            previous[] = cost_clock()
            Base.invokelatest(E.fit, model; prior=original.prior, init=original.initial,
                seed=original.seeds.advancedhmc, controls..., _sampling_observer=observer)
        end
        ended = cost_clock()
        push!(phases, (; phase=:result_construction, cost_delta(previous[], ended)...))
        fit = measured.value
        @assert length(transitions) == controls.warmup+controls.ndraws
        retained = filter(r -> r.phase === :retained, transitions)
        @assert getproperty.(retained,:n_steps) == getproperty.(fit.record.run.sampler_stats,:n_steps)
        @assert fit.record.target_identity == original.target_identity
        # Raw owned result avoids adding public cache/report compilation to this fit timer.
        serialize(joinpath(root,"fit.jls"), fit)
        writejson(joinpath(root,"phases.json"), phases)
        groups = [filter(r -> r.phase === phase, transitions) for phase in (:warmup,:retained)]
        phase_rows = [(; phase, iterations=length(rows),
            seconds=sum(r.seconds for r in rows), compile_seconds=sum(r.compile_seconds for r in rows),
            gc_seconds=sum(r.gc_seconds for r in rows), n_steps=sum(r.n_steps for r in rows),
            mean_depth=mean(r.tree_depth for r in rows), max_depth=maximum(r.tree_depth for r in rows),
            divergences=count(r.divergent for r in rows)) for (phase,rows) in zip((:warmup,:retained),groups)]
        # Explicit diagnostics call is outside fit and its profile, and may reuse compiled code.
        diagnostic = @timed Base.invokelatest(diagnostics, fit)
        @assert hashes == merge(source_hashes(), Dict(relpath(@__FILE__, REPO)=>digest(@__FILE__)))
        writejson(joinpath(root,"result.json"), (; status=:completed, phases, sampling=phase_rows,
            fit_seconds=measured.time, fit_compile_seconds=measured.compile_time,
            fit_gc_seconds=measured.gctime, fit_allocated_bytes=measured.bytes,
            observer_seconds=observer_seconds[], process_peak_rss_bytes=Sys.maxrss(),
            diagnostics_seconds=diagnostic.time, diagnostics_compile_seconds=diagnostic.compile_time,
            diagnostic_summary=diagnostic.value.summary,
            fit_sha256=digest(joinpath(root,"fit.jls")),
            scientific_acceptance=false, evaluation_replications=0))
    end
    for format in (:tree, :flat)
        open(joinpath(root,"profile-$(format).txt"), "w") do io
            Profile.print(io; format, C=true, mincount=10)
        end
    end
    serialize(joinpath(root,"profile.jls"), Profile.retrieve())
    println("Completed sampling cost probe: ", metric); flush(stdout)
end

if abspath(PROGRAM_FILE) == (@__FILE__)
    length(ARGS) == 3 || error("Usage: script.jl ORIGINAL_PILOT NEW_OUTPUT_DIRECTORY diagonal|dense")
    sampling_cost(abspath(ARGS[1]), abspath(ARGS[2]), Symbol(ARGS[3]))
end
