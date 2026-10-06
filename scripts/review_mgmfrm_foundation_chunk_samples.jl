# Read-only exact comparison of saved numerical runs; differences are results, not retries.
using BayesianMGMFRM, JSON3, Serialization, SHA
const B = BayesianMGMFRM
digest(path) = bytes2hex(sha256(read(path)))
function review(root, output)
    ispath(output) && error("Never replace a comparison result")
    plan = JSON3.read(read(joinpath(root, "plan.json"), String))
    repo = dirname(@__DIR__)
    study = JSON3.read(read(joinpath(repo, plan.study_plan), String))
    for (path, hash) in pairs(plan.source_sha256)
        digest(joinpath(repo, String(path))) == hash || error("Frozen source changed")
    end
    comparisons = NamedTuple[]
    for id in unique(a.study_id for a in plan.attempts)
        attempts = [only(filter(a -> a.study_id == id && a.chunk == c, plan.attempts)) for c in (12, 16)]
        records = map(attempts) do a
            path = joinpath(root, "attempts", a.id, "samples.jls")
            execution = JSON3.read(read(joinpath(dirname(path), "execution.json"), String))
            record = open(deserialize, path)
            expected = only(filter(a -> a.id == id, study.attempts)).target_identity
            @assert execution.samples_sha256 == digest(path)
            @assert record.target_identity == expected
            @assert record.content_hash == B._mgmfrm_normalized_sample_hash(record)
            @assert size(record.run.draws) == (4000, 128)
            record
        end
        a, b = records
        @assert keys(a.run) == keys(b.run)
        fields = Dict(String(k) => isequal(getproperty(a.run, k), getproperty(b.run, k)) for k in keys(a.run))
        original_path = joinpath(dirname(joinpath(repo, plan.study_plan)), "attempts", id, "samples.jls")
        original = open(deserialize, original_path)
        @assert original.content_hash == B._mgmfrm_normalized_sample_hash(original)
        push!(comparisons, (; study_id=id, fields, all_run_fields_equal=all(values(fields)),
            priors_equal=isequal(a.prior, b.prior), target_identity=a.target_identity,
            baseline_reproduces_original_run=isequal(a.run, original.run),
            original_samples_sha256=digest(original_path),
            content_hashes=[r.content_hash for r in records],
            maximum_draw_absolute_difference=maximum(abs.(a.run.draws .- b.run.draws)),
            maximum_logdensity_absolute_difference=maximum(abs.(a.run.logdensities .- b.run.logdensities))))
    end
    B._write_json_record(output, (; plan_sha256=digest(joinpath(root, "plan.json")),
        script_sha256=digest(@__FILE__), pairs=comparisons, scientific_acceptance=false))
    println("Saved exact numerical comparison for ", length(comparisons), " paired targets")
end
length(ARGS) == 2 || error("usage: review_mgmfrm_foundation_chunk_samples.jl ROOT NEW_OUTPUT")
review(abspath(ARGS[1]), abspath(ARGS[2]))
