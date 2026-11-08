module ReleaseMetadataChecks

using Test
include(joinpath(@__DIR__, "..", "scripts", "release_metadata.jl"))

@testset "Release version and citation consistency" begin
    root = dirname(@__DIR__)
    @test ReleaseMetadata.check(root) isa NamedTuple
    mktempdir() do dir
        write(joinpath(dir, "Project.toml"), "version = \"0.2.0\"\n")
        citation = "cff-version: 1.2.0\nversion: \"0.2.0\"\n"
        news = "# Release notes\n\n## 0.2.0 (unreleased)\n\n## 0.1.9 (2026-01-01)\n"
        function set_metadata(cff = citation, notes = news)
            write(joinpath(dir, "CITATION.cff"), cff)
            write(joinpath(dir, "NEWS.md"), notes)
        end
        set_metadata()
        @test ReleaseMetadata.check(dir).unreleased
        @test ReleaseMetadata.check(dir).date_released === nothing
        for value in ("0.2.0", "'0.2.0'", "\"0.2.0\" # selected version")
            set_metadata("version: $value\nreferences:\n  - version: 9.9.9\n")
            @test ReleaseMetadata.check(dir).version == v"0.2.0"
        end
        for bad_cff in (
            replace(citation, "0.2.0" => "0.1.9"),
            "cff-version: 1.2.0\n",
            citation * "version: 0.2.0\n",
            "version:\n  - 0.2.0\n",
            "version: \"0.2.0'\n",
            citation * "date-released: \"2026-01-01\"\n",
            citation * "date-released:\n",
        )
            set_metadata(bad_cff)
            @test_throws ErrorException ReleaseMetadata.check(dir)
        end
        for bad_news in (
            replace(news, "0.2.0" => "0.3.0"),
            "# Release notes\n",
            "## 0.2.0\n",
        )
            set_metadata(citation, bad_news)
            @test_throws ErrorException ReleaseMetadata.check(dir)
        end
        released = "## 0.2.0 (2026-10-19)\n"
        dated = citation * "date-released: \"2026-10-19\"\n"
        set_metadata(dated, released)
        @test !ReleaseMetadata.check(dir).unreleased
        @test ReleaseMetadata.check(dir).date_released == "2026-10-19"
        for bad_cff in (citation, replace(dated, "2026-10-19" => "2026-10-18"),
                       dated * "date-released: 2026-10-19\n")
            set_metadata(bad_cff, released)
            @test_throws ErrorException ReleaseMetadata.check(dir)
        end
        set_metadata(replace(dated, "2026-10-19" => "2026-02-30"),
                     "## 0.2.0 (2026-02-30)\n")
        @test_throws ArgumentError ReleaseMetadata.check(dir)
        set_metadata(replace(dated, "2026-10-19" => "2024-02-29"),
                     "## 0.2.0 (2024-02-29)\n")
        @test ReleaseMetadata.check(dir).date_released == "2024-02-29"
    end
end

end
