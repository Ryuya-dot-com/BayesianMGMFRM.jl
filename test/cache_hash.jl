module CacheHashChecks
using Test, SHA, BayesianMGMFRM
const B = BayesianMGMFRM

@testset "cache and report SHA-256 byte compatibility" begin
    # An independent byte-vector input avoids the CodeUnits performance problem.
    digest(text) = bytes2hex(sha256(Vector{UInt8}(codeunits(text))))
    canonical(value) = B._cache_stable_string(value)
    payload = (; label = "θ・評価\n\0", draws = [0.0 -0.0; Inf NaN],
        metadata = Dict("b" => missing, "a" => nothing))
    for value in (nothing, (), NamedTuple(), payload,
            merge(payload, (; draws = reverse(payload.draws; dims = 1))),
            (; values = reshape(collect(1:6000), 1000, 6)))
        @test B._cache_hash(value) == digest(canonical(value))
    end
    @test B._cache_hash(payload) != B._cache_hash(merge(payload, (; label = "changed")))
    @test B._cache_hash([0.0]) != B._cache_hash([-0.0])
    @test B._cache_hash(reshape(1:6, 2, 3)) != B._cache_hash(reshape(1:6, 3, 2))

    artifact = merge(payload, (; content_hash = "ignored",
        nested = (; value = 1, archive_manifest = "ignored")))
    stripped = B._artifact_hash_payload(artifact)
    json_payload = B._json_hash_value(stripped)
    table_payload = B._json_hash_value(B._artifact_hash_payload(B._json_export_value(artifact)))
    public_report = (; schema = B._FIT_REPORT_PUBLIC_SCHEMA,
        label = payload.label, values = [1.0, 2.0], content_hash = "ignored")
    public_payload = B._json_export_value(public_report)
    delete!(public_payload, "content_hash")
    for (record, expected) in (
            (B._artifact_content_hash_record(artifact), canonical(stripped)),
            (B._fit_report_json_hash_record(artifact), canonical(json_payload)),
            (B._public_fit_report_content_hash_record(public_report),
                canonical(B._json_hash_value(public_payload))),
            (B._fit_report_table_hash_record(artifact; scope = :test), canonical(table_payload)),
            (B._fit_report_dossier_json_hash_record(artifact), canonical(json_payload)))
        @test record.value == digest(expected)
        @test record.n_canonical_bytes == sizeof(expected)
        @test record.algorithm === :sha256
    end
    @test B.artifact_content_hash(artifact) == B._artifact_content_hash_record(artifact).value
    # SHA block and stream chunk boundaries, empty input, UTF-8 and embedded NUL.
    for markdown in ("", "θ・評価\n\0", SubString("xθyz", 2, 4), LazyString("θ", "・評価"),
            (repeat("a", n) for n in (63, 64, 65, 4095, 4096, 4097))...)
        for record in (B._fit_report_markdown_hash_record(markdown),
                B._fit_report_dossier_markdown_hash_record(markdown))
            @test record.value == digest(markdown)
            @test record.n_canonical_bytes == sizeof(markdown)
        end
    end
end
end
