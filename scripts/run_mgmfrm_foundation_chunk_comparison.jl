"""Research-only AD setting comparison; production sources and saved study stay fixed."""
module MGMFRMFoundationChunkComparison
using BayesianMGMFRM, JSON3, Dates, LinearAlgebra, Test
include("run_mgmfrm_foundation_sensitivity.jl")
const B = BayesianMGMFRM
const R = MGMFRMFoundationSensitivityRun
const F = R.F
const L = B.LogDensityProblems
const CHUNK = Ref(12)
const AD_CALLS = String[]

# Isolated process specialization. Chunk 12 delegates to the unchanged adapter;
# chunk 16 reuses its order-1 validation instead of replacing the sampler loop.
function B._logdensity_gradient_target(target::B._MGMFRMNormalizedLocationLogDensity,
        initial::AbstractVector, backend::Symbol)
    backend === :ForwardDiff || error("Comparison only supports ForwardDiff")
    L.dimension(target) == 128 || error("Comparison only supports the fixed 128-coordinate target")
    length(initial) == 128 || throw(ArgumentError("Wrong initial dimension"))
    result = if CHUNK[] == 12
        invoke(B._logdensity_gradient_target, Tuple{Any, AbstractVector, Symbol}, target, initial, backend)
    elseif CHUNK[] == 16
        ad = B.LogDensityProblemsAD.ADgradient(:ForwardDiff, target; x=initial, chunk=B.ForwardDiff.Chunk{16}())
        checked = B._logdensity_gradient_target(ad, initial, :analytic)
        merge(checked, (; ad_backend=:ForwardDiff, gradient_backend=:ad))
    else
        error("Unplanned chunk")
    end
    occursin("Chunk{$(CHUNK[])}", string(typeof(result.target))) || error("Wrong AD chunk")
    push!(AD_CALLS, string(typeof(result.target)))
    result
end

function bindings(plan, root)
    repo = dirname(@__DIR__)
    for (path, hash) in pairs(plan.source_sha256)
        F.digest(joinpath(repo, String(path))) == hash || error("Frozen source changed: $path")
    end
    F.digest(joinpath(repo, plan.study_plan)) == plan.study_plan_sha256 || error("Study plan changed")
    F.digest(joinpath(repo, plan.profile)) == plan.profile_sha256 || error("Saved states changed")
    isdir(root) || error("Comparison root missing")
end

function preflight(plan, root)
    bindings(plan, root)
    repo = dirname(@__DIR__)
    study = JSON3.read(read(joinpath(repo, plan.study_plan), String))
    profile = JSON3.read(read(joinpath(repo, plan.profile), String))
    @testset "Research chunk adapter preserves density and gradient" begin
        for previous in profile.reports
            a = only(filter(a -> a.id == previous.id, study.attempts))
            input = joinpath(repo, a.input)
            @test F.digest(input) == a.input_sha256
            p = F.prepare(input)
            prior = B.Experimental.NormalizedMGMFRMPrior(; prior_model=:exchangeable,
                merge(F.SCALES, (; log_discrimination_sd=Float64(a.log_discrimination_sd)))...)
            raw = B._normalized_mgmfrm_target(p.spec, prior)
            @test B._mgmfrm_normalized_prior_identity(raw) == a.target_identity
            target = B._MGMFRMNormalizedLocationLogDensity(raw)
            for point in previous.rawpoints
                x = B._mgmfrm_location_from_raw(target, Float64.(point))
                CHUNK[] = 12
                a12 = B._logdensity_gradient_target(target, x, :ForwardDiff)
                CHUNK[] = 16
                a16 = B._logdensity_gradient_target(target, x, :ForwardDiff)
                v12, g12 = L.logdensity_and_gradient(a12.target, x)
                v16, g16 = L.logdensity_and_gradient(a16.target, x)
                @test v12 == v16
                @test g12 == g16
                @test a12.ad_backend == a16.ad_backend == :ForwardDiff
                @test a12.gradient_backend == a16.gradient_backend == :ad
            end
            @test_throws ArgumentError B._logdensity_gradient_target(target, zeros(127), :ForwardDiff)
        end
    end
    bindings(plan, root)
    empty!(AD_CALLS)
end

function run(root)
    plan_path = joinpath(root, "plan.json")
    plan = JSON3.read(read(plan_path, String))
    plan.schema == "mgmfrm.foundation_chunk_comparison.v1" && plan.evaluation_credit == 0 || error("Wrong scope")
    plan_hash = F.digest(plan_path)
    preflight(plan, root)
    B._write_json_record(joinpath(root, "preflight.json"), (; passed=true, plan_sha256=plan_hash,
        created_utc=string(now(UTC)), julia_version=string(VERSION), threads=Threads.nthreads(),
        blas_threads=BLAS.get_num_threads(), independent_evaluation_credit=0))
    for a in plan.attempts
        F.digest(plan_path) == plan_hash || error("Comparison plan changed")
        bindings(plan, root)
        CHUNK[] = Int(a.chunk)
        empty!(AD_CALLS)
        output = joinpath(root, "attempts", a.id)
        ispath(output) && error("Never replace a started comparison")
        B._write_json_record(joinpath(root, "$(a.id)-setting.json"), (; attempt=a,
            plan_sha256=plan_hash, created_utc=string(now(UTC)), evaluation_credit=0))
        println(now(UTC), " comparison ", a.id, " start"); flush(stdout)
        measured = @timed R.run(joinpath(dirname(@__DIR__), plan.study_plan), a.study_id, output)
        length(AD_CALLS) == 4 || error("Expected one AD adapter per chain")
        B._write_json_record(joinpath(root, "$(a.id)-timing.json"), (; attempt=a,
            plan_sha256=plan_hash, seconds=measured.time, compile_seconds=measured.compile_time,
            gc_seconds=measured.gctime, allocated_bytes=measured.bytes,
            adapter_types=copy(AD_CALLS), finished_utc=string(now(UTC)), evaluation_credit=0))
        println(now(UTC), " comparison ", a.id, " complete"); flush(stdout)
        GC.gc()
    end
    bindings(plan, root)
    B._write_json_record(joinpath(root, "completed.json"), (; plan_sha256=plan_hash,
        attempts=length(plan.attempts), finished_utc=string(now(UTC)), scientific_acceptance=false))
end
end

if abspath(PROGRAM_FILE) == @__FILE__
    length(ARGS) == 2 || error("usage: run_mgmfrm_foundation_chunk_comparison.jl preflight|run ROOT")
    root = abspath(ARGS[2])
    if ARGS[1] == "preflight"
        plan = MGMFRMFoundationChunkComparison.JSON3.read(read(joinpath(root, "plan.json"), String))
        MGMFRMFoundationChunkComparison.preflight(plan, root)
    elseif ARGS[1] == "run"
        MGMFRMFoundationChunkComparison.run(root)
    else
        error("Unknown action")
    end
end
