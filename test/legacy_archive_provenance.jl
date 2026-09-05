using JSON3
using SHA
using Test

@testset "opt-in legacy archive provenance classification" begin
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
