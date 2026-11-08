module ReportIntegerChecksumChecks
using Test, BayesianMGMFRM
const B = BayesianMGMFRM
const exact = :cache_stable_string_exact_integers_v1
hashof(x; canonicalization = exact) =
    B._fit_report_json_hash_record(x; canonicalization).value

function checks()
    @testset "Versioned exact-integer report checksum" begin
        mktempdir() do dir
            path = joinpath(dir, "report.json")
            id = UInt64(0xc9c209ecb5532375)
            @test Float64(id) == Float64(id + 1)
            @test hashof(Dict("id" => id); canonicalization = :cache_stable_string) ==
                hashof(Dict("id" => id + 1); canonicalization = :cache_stable_string)
            @test hashof(Dict("id" => id)) != hashof(Dict("id" => id + 1))
            for n in (big(typemin(Int64))-1, big(typemin(Int64)), big(2)^53+1,
                    big(typemax(Int64)), big(id), big(typemax(UInt64)), big(2)^80)
                payload = Dict("id" => n, "nested" => Any[.5, n, -0.0],
                    "text" => string(n), "flag" => true, "null" => nothing)
                B._write_json_record(path, payload)
                got = B._read_json_dict(path, "finite hash input")
                @test hashof(payload) == hashof(got)
                changed = deepcopy(payload); changed["id"] += 1
                @test hashof(payload) != hashof(changed)
                changed = deepcopy(payload); changed["nested"][2] += 1
                @test hashof(payload) != hashof(changed)
            end
            @test hashof(Dict("id" => UInt64(7))) == hashof(Dict("id" => Int8(7))) ==
                hashof(Dict("id" => big(7)))
            for x in (true, "1", 1.0, nothing)
                @test hashof(Dict("x" => 1)) != hashof(Dict("x" => x))
            end
            @test hashof(Dict("x" => -0.0)) != hashof(Dict("x" => 0.0))
            @test hashof(Dict("a" => 1, "b" => 2)) == hashof(Dict("b" => 2, "a" => 1))
            @test_throws ArgumentError hashof(Dict(); canonicalization = :unknown)

            report = (; schema = "bayesianmgmfrm.fit_report.v1", object = :fit_report,
                family = :mfrm, created_at = "fixed fixture", estimation_status = :fit_supported,
                metadata = (; data_signature = id),
                posterior = (; status = :computed,
                    rows = [(; parameter = "rater[2]", median = -0.0)], n_rows = 1))
            record = save_fit_report(path, report; overwrite = true)
            @test record.schema == "bayesianmgmfrm.fit_report_export.v2"
            @test record.json_content_hash.canonicalization === exact
            @test isequal(load_fit_report(path), B._json_export_value(report))
            @test_throws ArgumentError save_fit_report(path, report)
            baseline = B._read_json_dict(path, "new report")
            changed = deepcopy(baseline)
            changed["report"]["metadata"]["data_signature"] += 1
            B._write_json_record(path, changed)
            @test_throws ArgumentError load_fit_report(path)
            @test load_fit_report(path; verify_hash = false)["metadata"]["data_signature"] == id + 1

            legacy = deepcopy(baseline)
            legacy["schema"] = "bayesianmgmfrm.fit_report_export.v1"
            legacy["json_content_hash"] = B._json_export_value(
                B._fit_report_json_hash_record(legacy["report"]))
            B._write_json_record(path, legacy)
            @test isequal(load_fit_report(path), B._json_export_value(report))
            legacy["report"]["metadata"]["data_signature"] += 1
            B._write_json_record(path, legacy)
            # Retain the historical limitation; reading v1 cannot upgrade its proof.
            @test load_fit_report(path)["metadata"]["data_signature"] == id + 1
            for (field, value) in (("schema", "bayesianmgmfrm.fit_report_export.v99"),
                    ("schema", "bayesianmgmfrm.fit_report_export.v1"),
                    ("canonicalization", "cache_stable_string"),
                    ("canonicalization", "unknown"), ("n_canonical_bytes", true),
                    ("scope", "wrong_scope"))
                changed = deepcopy(baseline)
                field == "schema" ? (changed[field] = value) :
                    (changed["json_content_hash"][field] = value)
                B._write_json_record(path, changed)
                @test_throws ArgumentError load_fit_report(path; verify_hash = false)
            end

            for (i, value) in enumerate((report, fit_report_public(report)))
                bundle = joinpath(dir, "bundle-$i")
                manifest = save_fit_report_bundle(bundle, value)
                @test manifest.schema == "bayesianmgmfrm.fit_report_bundle_export.v1"
                @test manifest.files[1].schema == "bayesianmgmfrm.fit_report_export.v2"
                @test manifest.files[1].content_hash.canonicalization === exact
                @test isequal(load_fit_report_bundle(bundle), B._json_export_value(value))
                @test load_fit_report_bundle(bundle; return_manifest = true)["content_hash"]["value"] == manifest.content_hash.value
                mpath = joinpath(bundle, "manifest.json")
                changed = B._read_json_dict(mpath, "bundle manifest")
                changed["files"][1]["schema"] = "bayesianmgmfrm.fit_report_export.v1"
                B._write_json_record(mpath, changed)
                @test_throws ArgumentError load_fit_report_bundle(bundle; verify_hash = false, return_manifest = true)
            end
        end
    end
end
end
