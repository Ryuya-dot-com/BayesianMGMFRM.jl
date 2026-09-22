module NormalizedPriorResultProfile

using BayesianMGMFRM, JSON3, Profile, Serialization, SHA
const B = BayesianMGMFRM
include("run_normalized_prior_comparison.jl")
const C = NormalizedPriorComparison

# Recompute the original four-fit receipt without sampling or rewriting inputs.
function verify_comparison(input::AbstractString, output::AbstractString)
    ispath(output) && throw(ArgumentError("verification output must be new"))
    read_json(path) = JSON3.read(read(joinpath(input, path), String), Dict{String,Any})
    files = filter(p -> isfile(joinpath(input, p)) && splitext(p)[2] in (".json", ".jls"), readdir(input))
    hashes() = [(; path = p, sha256 = bytes2hex(sha256(read(joinpath(input, p))))) for p in files]
    original_hashes, sources = hashes(), C.source_hashes()
    original = read_json("comparison.json")
    @assert B._cache_hash(open(deserialize, joinpath(input, "protocol.jls"))) == original["protocol_hash"]
    receipts = NamedTuple[]
    for target in C.targets()
        fits = NamedTuple[]
        for backend in (:advancedhmc, :cmdstan)
            summary = read_json("$(target.prior_model)-$backend-summary.json")
            path = joinpath(input, summary["sample_file"])
            @assert bytes2hex(sha256(read(path))) == summary["sample_file_sha256"]
            result = B._load_mgmfrm_normalized_prior_samples(path;
                expected_identity = B._mgmfrm_normalized_prior_identity(target))
            @assert result.record.content_hash == summary["sample_content_hash"]
            values = C.comparison_input(target, result)
            parameters = C.summarize(values.draws, values.names, result.record.run.controls.chains)
            diagnostic = C.fit_diagnostics(result, parameters)
            for (name, value) in (("parameters", parameters), ("diagnostic", diagnostic),
                    ("sampler_rows", result.record.run.sampler_rows),
                    ("sampler_controls", result.record.run.controls))
                @assert isequal(B._json_export_value(value), summary[name])
            end
            push!(fits, (; parameters, diagnostic))
            println("Verified saved ", target.prior_model, " ", backend); flush(stdout)
        end
        rows = C.compare(fits[1].parameters, fits[2].parameters;
            diagnostic_passed = all(f -> f.diagnostic.passed, fits))
        pair = read_json("$(target.prior_model)-comparison.json")
        @assert isequal(B._json_export_value(rows), pair["rows"])
        push!(receipts, (; prior_model = target.prior_model, rows = length(rows),
            within_resolution = count(r -> r.status === :within_resolution, rows),
            unresolved = count(r -> r.status !== :within_resolution, rows)))
    end
    @assert hashes() == original_hashes && C.source_hashes() == sources
    report = (; input_hashes = original_hashes, source_hashes = sources,
        script_sha256 = bytes2hex(sha256(read(@__FILE__))), receipts,
        scope = :saved_draw_integrity_and_exact_summary_recomputation_no_sampling)
    B._write_json_record(output, report)
    return report
end

# Manual, one existing 6,000-draw record; no fitting or input-file writes.
function run(input::AbstractString, output::AbstractString; reference = nothing)
    ispath(output) && throw(ArgumentError("profile output must be a new directory"))
    manifest = JSON3.read(read(joinpath(input, "exchangeable-advancedhmc-summary.json"), String))
    path = joinpath(input, String(manifest.sample_file))
    input_hash = bytes2hex(sha256(read(path)))
    input_hash == manifest.sample_file_sha256 || error("input sample hash mismatch")
    source_before = C.source_hashes()
    mkpath(output)
    timings = NamedTuple[]
    function measure(f, label)
        GC.gc()
        measured = @timed f()
        row = (; stage = label, seconds = measured.time, bytes = measured.bytes,
            gc_seconds = measured.gctime, compile_seconds = get(measured, :compile_time, missing))
        push!(timings, row)
        println(row); flush(stdout)
        return measured.value
    end
    record = measure(:deserialize) do
        open(deserialize, path)
    end
    target = measure(:target_identity) do
        B._MGMFRMNormalizedPriorLogDensity(record.spec, record.prior;
            expected_identity = record.target_identity)
    end
    Profile.init(n = 5_000_000, delay = 0.01)
    Profile.clear()
    result, parameters = Profile.@profile begin
        measure(:payload_hash) do
            @assert B._mgmfrm_normalized_sample_hash(record) == record.content_hash
        end
        measure(:run_validation) do
            B._check_mgmfrm_normalized_prior_run(target, record.run)
        end
        tables = measure(:diagnostic_tables) do
            B._generalized_candidate_diagnostic_tables(target.base, record.run)
        end
        result = (; record, public_fit = false,
            raw_parameter_names = copy(target.base.blueprint.parameter_names),
            direct_parameter_names = copy(target.base.blueprint.constrained_parameter_names),
            diagnostics = tables)
        parameters = measure(:comparison_summaries) do
            values = C.comparison_input(target, result)
            C.summarize(values.draws, values.names, record.run.controls.chains)
        end
        measure(:atomic_serialization_only) do
            B._save_serialized_record(joinpath(output, "serialization-only.jls"), record)
        end
        measure(:save_with_validation) do
            B._save_mgmfrm_normalized_prior_samples(joinpath(output, "saved.jls"), result)
        end
        loaded = measure(:load_with_validation) do
            B._load_mgmfrm_normalized_prior_samples(joinpath(output, "saved.jls");
                expected_identity = record.target_identity)
        end
        @assert isequal(loaded.record.run, record.run)
        @assert isequal(loaded.diagnostics, tables)
        (result, parameters)
    end
    open(joinpath(output, "profile-flat.txt"), "w") do io
        Profile.print(io; format = :flat, sortedby = :count, mincount = 20)
    end
    open(joinpath(output, "profile-tree.txt"), "w") do io
        Profile.print(io; format = :tree, mincount = 20, maxdepth = 32)
    end
    if reference !== nothing
        before = open(deserialize, reference)
        # FacetSpec has identity equality; validate its canonical target separately.
        B._MGMFRMNormalizedPriorLogDensity(before.result.record.spec, before.result.record.prior;
            expected_identity = record.target_identity)
        @assert before.result.record.content_hash == record.content_hash
        @assert isequal(before.result.record.run, record.run)
        @assert isequal(Base.structdiff(before.result, (; record = nothing)),
            Base.structdiff(result, (; record = nothing)))
        @assert isequal(before.parameters, parameters)
    end
    B._save_serialized_record(joinpath(output, "reference.jls"), (; result, parameters))
    @assert bytes2hex(sha256(read(path))) == input_hash
    @assert C.source_hashes() == source_before
    report = (; schema = "bayesianmgmfrm.normalized_result_profile.v1",
        julia_version = string(VERSION), input_hash, target_identity = record.target_identity,
        profiler_interval_seconds = 0.01, source_hashes = source_before,
        script_sha256 = bytes2hex(sha256(read(@__FILE__))),
        reference_verified = reference !== nothing, timings,
        scope = :single_local_profile_includes_jit_not_benchmark)
    B._write_json_record(joinpath(output, "timings.json"), report)
    println("PROFILE COMPLETE; input unchanged; saved and loaded results identical.")
    return report
end

end

if abspath(PROGRAM_FILE) == @__FILE__
    length(ARGS) in (2, 3) || error("usage: julia --project=. scripts/profile_normalized_prior_results.jl INPUT_DIRECTORY NEW_OUTPUT_DIRECTORY [REFERENCE_JLS]")
    NormalizedPriorResultProfile.run(ARGS[1], ARGS[2]; reference = length(ARGS) == 3 ? ARGS[3] : nothing)
end
