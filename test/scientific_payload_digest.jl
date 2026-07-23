using JSON3
using SHA
using Test

if !isdefined(@__MODULE__, :ScientificPayloadDigest)
    include(joinpath(
        @__DIR__,
        "..",
        "scripts",
        "scientific_payload_digest.jl",
    ))
end

const SPD = ScientificPayloadDigest
const SYNTHETIC_PAYLOAD_CONTRACT = SPD.ScientificPayloadSchemaContract(
    "bayesianmgmfrm.synthetic_scientific_payload.v1";
    required_fields = (
        :schema,
        :family,
        :data_content_sha256,
        :q_rows,
        :prior,
        :seed,
        :sampler,
        :result,
    ),
)

@testset "scientific payload digest contract" begin
    golden_payload = (;
        nested = (; z = -0.0, alpha = "μ"),
        a = Any[1.0, true, nothing],
    )
    golden_json = "{\"a\":[1,true,null],\"nested\":{\"alpha\":\"μ\",\"z\":0}}"
    golden_sha256 =
        "4ac9af30f63ebea9025b0226552cd6cd0dfff4a47a3e131ced9705344b9d1554"
    canonical = SPD.canonical_json_bytes(golden_payload)
    @test length(canonical) == 49
    @test String(copy(canonical)) == golden_json
    @test SPD.canonical_json_sha256(golden_payload) == golden_sha256
    @test SPD.scientific_payload_sha256(JSON3.read(golden_json)) ==
        golden_sha256

    reordered = Dict{String,Any}(
        "a" => Any[1, true, nothing],
        "nested" => Dict("z" => 0, "alpha" => "μ"),
    )
    @test SPD.scientific_payload_sha256(reordered) == golden_sha256
    @test SPD.scientific_payload_sha256((; values = [1, 2])) !=
        SPD.scientific_payload_sha256((; values = [2, 1]))

    base_artifact = (;
        scientific = (;
            schema = "bayesianmgmfrm.synthetic_scientific_payload.v1",
            family = :mgmfrm,
            data_content_sha256 = repeat("a", 64),
            q_rows = [[true, false], [false, true]],
            prior = (; correlation_eta = 2.0),
            seed = 20260722,
            sampler = (; warmup = 500, draws = 500, chains = 4),
            result = (; estimate = 0.25, decision = :retain),
        ),
        package = (; julia_version = "1.10.8"),
        generated_at = "2026-07-22T00:00:00",
        generator_source_sha256 = repeat("b", 64),
        documentation_sha256 = repeat("c", 64),
    )
    provenance_changed = merge(base_artifact, (;
        package = (; julia_version = "1.12.5"),
        generated_at = "2026-07-23T00:00:00",
        generator_source_sha256 = repeat("d", 64),
        documentation_sha256 = repeat("e", 64),
    ))
    base_digest = SPD.scientific_payload_sha256(
        base_artifact.scientific,
        SYNTHETIC_PAYLOAD_CONTRACT,
    )
    @test SPD.scientific_payload_sha256(
        provenance_changed.scientific,
        SYNTHETIC_PAYLOAD_CONTRACT,
    ) == base_digest
    @test bytes2hex(sha256(codeunits(repr(base_artifact)))) !=
        bytes2hex(sha256(codeunits(repr(provenance_changed))))

    data_changed = merge(base_artifact.scientific, (;
        data_content_sha256 = repeat("f", 64),
    ))
    result_changed = merge(base_artifact.scientific, (;
        result = (; estimate = 0.30, decision = :retain),
    ))
    seed_changed = merge(base_artifact.scientific, (; seed = 20260723))
    decision_changed = merge(base_artifact.scientific, (;
        result = (; estimate = 0.25, decision = :reject),
    ))
    @test SPD.scientific_payload_sha256(
        data_changed,
        SYNTHETIC_PAYLOAD_CONTRACT,
    ) != base_digest
    @test SPD.scientific_payload_sha256(
        result_changed,
        SYNTHETIC_PAYLOAD_CONTRACT,
    ) != base_digest
    @test SPD.scientific_payload_sha256(
        seed_changed,
        SYNTHETIC_PAYLOAD_CONTRACT,
    ) != base_digest
    @test SPD.scientific_payload_sha256(
        decision_changed,
        SYNTHETIC_PAYLOAD_CONTRACT,
    ) != base_digest

    @test_throws ArgumentError SPD.scientific_payload_sha256((; value = NaN))
    @test_throws ArgumentError SPD.scientific_payload_sha256((; value = Inf))
    @test_throws ArgumentError SPD.scientific_payload_sha256((; value = missing))
    @test_throws ArgumentError SPD.scientific_payload_sha256((; value = Float16(0.5)))
    @test_throws ArgumentError SPD.scientific_payload_sha256((; value = Float32(0.5)))
    @test_throws ArgumentError SPD.scientific_payload_sha256((; value = BigFloat(0.5)))
    @test_throws ArgumentError SPD.scientific_payload_sha256((; q = [1 0; 0 1]))
    @test_throws ArgumentError SPD.scientific_payload_sha256(
        Dict{Any,Any}(:x => 1, "x" => 2),
    )
    @test_throws ArgumentError SPD.scientific_payload_sha256(
        Dict{Any,Any}(1 => "not a JSON object key"),
    )

    @test_throws ArgumentError SPD.ScientificPayloadSchemaContract(
        "schema-only.v1";
        required_fields = (:schema,),
    )
    @test_throws ArgumentError SPD.ScientificPayloadSchemaContract(
        "duplicate.v1";
        required_fields = (:schema, :value, "value"),
    )
    @test_throws ArgumentError SPD.ScientificPayloadSchemaContract(
        "overlap.v1";
        required_fields = (:schema, :value),
        optional_fields = (:value,),
    )
    @test_throws ArgumentError SPD.ScientificPayloadSchemaContract(
        "schema-only.v1",
        ("schema",),
        (),
    )

    invalid_utf8 = String(UInt8[0xff])
    @test !isvalid(invalid_utf8)
    @test_throws ArgumentError SPD.scientific_payload_sha256((;
        value = invalid_utf8,
    ))
    @test_throws ArgumentError SPD.scientific_payload_sha256(
        Dict(invalid_utf8 => 1),
    )
    @test_throws ArgumentError SPD.ScientificPayloadSchemaContract(
        invalid_utf8;
        required_fields = (:schema, :value),
    )
    @test_throws ArgumentError SPD.ScientificPayloadSchemaContract(
        "invalid-field.v1";
        required_fields = (:schema, invalid_utf8),
    )
    @test_throws ArgumentError SPD.scientific_payload_sha256(
        JSON3.read("{\"x\":1,\"x\":2}"),
    )

    recorded = (;
        scientific_payload = base_artifact.scientific,
        scientific_payload_sha256 = base_digest,
    )
    @test SPD.recorded_scientific_payload_sha256(
        recorded;
        schema_contract = SYNTHETIC_PAYLOAD_CONTRACT,
    ) == base_digest
    json3_recorded = JSON3.read(JSON3.write(recorded))
    @test SPD.recorded_scientific_payload_sha256(
        json3_recorded;
        schema_contract = SYNTHETIC_PAYLOAD_CONTRACT,
    ) == base_digest
    @test SPD.verify_scientific_payload_sha256(
        base_artifact.scientific,
        base_digest,
        SYNTHETIC_PAYLOAD_CONTRACT,
    ) == base_digest
    @test_throws ArgumentError SPD.recorded_scientific_payload_sha256(recorded)
    @test_throws ArgumentError SPD.recorded_scientific_payload_sha256((;
        scientific_payload = base_artifact.scientific,
    ); schema_contract = SYNTHETIC_PAYLOAD_CONTRACT)
    @test_throws ArgumentError SPD.recorded_scientific_payload_sha256((;
        scientific_payload_sha256 = base_digest,
    ); schema_contract = SYNTHETIC_PAYLOAD_CONTRACT)
    @test_throws ArgumentError SPD.recorded_scientific_payload_sha256((;
        scientific_payload = base_artifact.scientific,
        scientific_payload_sha256 = uppercase(base_digest),
    ); schema_contract = SYNTHETIC_PAYLOAD_CONTRACT)
    @test_throws ArgumentError SPD.recorded_scientific_payload_sha256((;
        scientific_payload = result_changed,
        scientific_payload_sha256 = base_digest,
    ); schema_contract = SYNTHETIC_PAYLOAD_CONTRACT)
    @test_throws ArgumentError SPD.recorded_scientific_payload_sha256(
        Dict{Any,Any}(
            :scientific_payload => base_artifact.scientific,
            "scientific_payload" => base_artifact.scientific,
            :scientific_payload_sha256 => base_digest,
        );
        schema_contract = SYNTHETIC_PAYLOAD_CONTRACT,
    )
    duplicate_json_artifact = JSON3.read(
        "{\"scientific_payload\":{},\"scientific_payload\":{}," *
        "\"scientific_payload_sha256\":\"$(repeat("0", 64))\"}",
    )
    @test_throws ArgumentError SPD.recorded_scientific_payload_sha256(
        duplicate_json_artifact;
        schema_contract = SYNTHETIC_PAYLOAD_CONTRACT,
    )

    empty_payload = Dict{String,Any}()
    empty_digest = SPD.scientific_payload_sha256(empty_payload)
    @test_throws ArgumentError SPD.recorded_scientific_payload_sha256((;
        scientific_payload = empty_payload,
        scientific_payload_sha256 = empty_digest,
    ); schema_contract = SYNTHETIC_PAYLOAD_CONTRACT)
    null_digest = SPD.scientific_payload_sha256(nothing)
    @test_throws ArgumentError SPD.recorded_scientific_payload_sha256((;
        scientific_payload = nothing,
        scientific_payload_sha256 = null_digest,
    ); schema_contract = SYNTHETIC_PAYLOAD_CONTRACT)
    schema_only = Dict("schema" => SYNTHETIC_PAYLOAD_CONTRACT.schema)
    @test_throws ArgumentError SPD.recorded_scientific_payload_sha256((;
        scientific_payload = schema_only,
        scientific_payload_sha256 = SPD.scientific_payload_sha256(schema_only),
    ); schema_contract = SYNTHETIC_PAYLOAD_CONTRACT)
    wrong_schema = merge(base_artifact.scientific, (; schema = "wrong.v1"))
    @test_throws ArgumentError SPD.scientific_payload_sha256(
        wrong_schema,
        SYNTHETIC_PAYLOAD_CONTRACT,
    )
    extra_field = merge(base_artifact.scientific, (; undocumented = 1))
    @test_throws ArgumentError SPD.scientific_payload_sha256(
        extra_field,
        SYNTHETIC_PAYLOAD_CONTRACT,
    )

    legacy_path = joinpath(
        @__DIR__,
        "fixtures",
        "gmfrm_guarded_fit_api_dry_run.json",
    )
    legacy = JSON3.read(read(legacy_path, String))
    @test ismissing(SPD.recorded_scientific_payload_sha256(
        legacy;
        allow_legacy = true,
    ))
    @test_throws ArgumentError SPD.recorded_scientific_payload_sha256(legacy)

    env_name = "BAYESIANMGMFRM_STRICT_ARCHIVE_SHA"
    withenv(env_name => nothing) do
        @test !SPD.strict_archive_sha_enabled()
    end
    for value in ("1", "TRUE", " yes ", "On")
        withenv(env_name => value) do
            @test SPD.strict_archive_sha_enabled()
        end
    end
    for value in ("", "0", "FALSE", " no ", "Off")
        withenv(env_name => value) do
            @test !SPD.strict_archive_sha_enabled()
        end
    end
    withenv(env_name => "truthy") do
        @test_throws ArgumentError SPD.strict_archive_sha_enabled()
    end

    exact_reference = SPD.reference_integrity_status(
        repeat("1", 64),
        repeat("1", 64);
        reference_kind = :generated_artifact,
    )
    @test exact_reference.status === :exact_file_match
    @test exact_reference.provenance_policy_accepted
    @test exact_reference.exact_file_sha256_verified
    @test !exact_reference.scientific_equivalence_verified
    @test !exact_reference.archive_refresh_required

    provenance_drift = SPD.reference_integrity_status(
        repeat("1", 64),
        repeat("2", 64);
        reference_kind = :code_doc,
        strict = false,
    )
    @test provenance_drift.status === :provenance_drift
    @test provenance_drift.provenance_policy_accepted
    @test !provenance_drift.exact_file_sha256_verified
    @test !provenance_drift.scientific_equivalence_verified
    @test provenance_drift.archive_refresh_required
    @test !SPD.reference_integrity_status(
        repeat("1", 64),
        repeat("2", 64);
        reference_kind = :code_doc,
        strict = true,
    ).provenance_policy_accepted
    @test !SPD.reference_integrity_status(
        repeat("1", 64),
        repeat("2", 64);
        reference_kind = :raw_data,
        strict = false,
    ).provenance_policy_accepted
    @test_throws ArgumentError SPD.reference_integrity_status(
        "not-a-sha",
        repeat("2", 64);
        reference_kind = :code_doc,
    )
end

@testset "legacy archive provenance classification" begin
    root = normpath(joinpath(@__DIR__, ".."))
    file_digest(path) = bytes2hex(open(sha256, path))
    strict_archive = "--strict-archive" in ARGS ||
        SPD.strict_archive_sha_enabled()
    records = NamedTuple[]

    dry_run = JSON3.read(read(joinpath(
        @__DIR__,
        "fixtures",
        "gmfrm_guarded_fit_api_dry_run.json",
    ), String))
    for row in dry_run.evidence_reference_rows
        String(row.reference_kind) == "local_file" || continue
        path = first(split(String(row.artifact), '#'; limit = 2))
        reference_kind = splitext(path)[2] in
            (".jl", ".md", ".toml", ".yml", ".yaml") ?
            :code_doc : :generated_artifact
        push!(records, (;
            fixture = "gmfrm_guarded_fit_api_dry_run.json",
            path,
            integrity = SPD.reference_integrity_status(
                String(row.sha256),
                file_digest(joinpath(root, path));
                reference_kind,
                strict = strict_archive,
            ),
        ))
    end

    for fixture_name in (
            "gmfrm_claim_recovery_reproduction_archive.json",
            "gmfrm_full_paper_reproduction_archive.json")
        fixture = JSON3.read(read(joinpath(
            @__DIR__,
            "fixtures",
            fixture_name,
        ), String))
        for row in fixture.code_doc_records
            path = String(row.path)
            push!(records, (;
                fixture = fixture_name,
                path,
                integrity = SPD.reference_integrity_status(
                    String(row.sha256),
                    file_digest(joinpath(root, path));
                    reference_kind = :code_doc,
                    strict = strict_archive,
                ),
            ))
        end
    end

    drift_paths = ["$(row.fixture):$(row.path)" for row in records
        if row.integrity.status === :provenance_drift]
    if !isempty(drift_paths)
        @info "legacy archive code/document provenance drift" strict_archive = strict_archive count = length(drift_paths)
        for path in drift_paths
            @info "legacy archive provenance drift path" path
        end
    end

    @test !isempty(records)
    @test all(row -> row.integrity.provenance_policy_accepted, records)
    @test !any(row -> row.integrity.status === :integrity_mismatch, records)
    @test all(row -> !row.integrity.scientific_equivalence_verified, records)
end
