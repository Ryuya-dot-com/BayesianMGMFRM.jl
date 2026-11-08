module ReportBundlePreflightChecks
using BayesianMGMFRM, Test, SHA

fixture() = (; schema="bayesianmgmfrm.fit_report.v1", object=:fit_report,
    created_at="2026-10-15T00:00:00", family=:mfrm, thresholds=:partial_credit,
    dimensions=1, dimension_labels=["ability"], estimation_status=:fit_supported,
    status_policy=(;status_label=:fit_supported),
    posterior=(;status=:computed, rows=[(;parameter="person[P1]", mean=0.0)], n_rows=1),
    artifact=(;status=:not_requested))

file_hashes(directory) = Dict(relpath(joinpath(dir,f),directory) =>
    bytes2hex(sha256(read(joinpath(dir,f))))
    for (dir,_,files) in walkdir(directory) for f in files)

function checks(report=fixture())
    @testset "Report bundle option validation preserves output" begin
        mktempdir() do directory
            fresh = joinpath(directory,"fresh")
            @test_throws ArgumentError save_fit_report_bundle(fresh,report;
                max_rows=-1, require_complete=true)
            @test !ispath(fresh)
            existing = joinpath(directory,"existing")
            # Zero is valid: omit preview rows, while retaining the full report.
            save_fit_report_bundle(existing,report; max_rows=0, require_complete=true)
            original = load_fit_report_bundle(existing; require_complete=true)
            write(joinpath(existing,"reader-notes.txt"),"Keep these notes.\n")
            before = file_hashes(existing)
            @test_throws ArgumentError save_fit_report_bundle(existing,report;
                overwrite=true, max_rows=-1, label="invalid replacement", require_complete=true)
            @test file_hashes(existing) == before
            @test isequal(load_fit_report_bundle(existing; require_complete=true),original)
            @test_throws ArgumentError save_fit_report_bundle(existing,report;
                max_rows=2, require_complete=true)
            @test file_hashes(existing) == before
            save_fit_report_bundle(existing,report; overwrite=true, max_rows=2,
                label="valid replacement", require_complete=true)
            @test isequal(load_fit_report_bundle(existing; require_complete=true),original)
            @test read(joinpath(existing,"reader-notes.txt"),String) == "Keep these notes.\n"
        end
    end
end
end

ReportBundlePreflightChecks.checks()
