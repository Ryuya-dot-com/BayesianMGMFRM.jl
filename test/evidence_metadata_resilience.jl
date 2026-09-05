using BayesianMGMFRM
using Test

const _run_evidence_optional = getfield(
    BayesianMGMFRM,
    :_evidence_optional,
)
const _try_read_evidence_command = getfield(
    BayesianMGMFRM,
    :_evidence_try_read,
)

@testset "evidence metadata remains usable after optional probe failure" begin
    issues = Any[]
    available = _run_evidence_optional(:unit_probe; issues) do
        "available"
    end
    @test available == "available"
    @test isempty(issues)

    unavailable = _run_evidence_optional(
        :unit_probe;
        issues,
        fallback = "fallback",
    ) do
        throw(ArgumentError("expected test failure"))
    end
    @test unavailable == "fallback"
    @test only(issues) == (;
        status = :unavailable,
        stage = :unit_probe,
        reason = :invalid_value,
    )

    noisy_issues = Any[]
    noisy_command = `$(Base.julia_cmd()) --startup-file=no -e "println(stderr, \"optional probe noise\"); exit(1)"`
    noisy_result, stderr_text = mktemp() do _, captured_stderr
        result = redirect_stderr(captured_stderr) do
            _try_read_evidence_command(
                noisy_command;
                issues = noisy_issues,
                stage = :noisy_command,
            )
        end
        flush(captured_stderr)
        seekstart(captured_stderr)
        return result, read(captured_stderr, String)
    end
    @test isnothing(noisy_result)
    @test isempty(stderr_text)
    @test only(noisy_issues).stage === :noisy_command
    @test only(noisy_issues).reason === :command_failed

    metadata = evidence_metadata(; include_packages = false)
    @test metadata["collection"]["status"] in (:complete, :partial)
    @test haskey(metadata, "git")
    @test haskey(metadata, "hashes")
    @test haskey(metadata["hashes"], "active_project_sha256")
    @test metadata["hashes"]["active_project"] === nothing
    @test metadata["software"]["julia"]["project"] === nothing
    @test all(
        issue -> issue.status === :unavailable &&
            issue.stage isa Symbol && issue.reason isa Symbol,
        metadata["collection"]["issues"],
    )
    @test metadata["packages"] == Dict{String,Any}()

    metadata_with_packages = evidence_metadata()
    @test metadata_with_packages["packages"] isa Dict{String,Any}

    withenv("PATH" => "") do
        degraded = evidence_metadata(; include_packages = false)
        issue_stages = Set(issue.stage for issue in
            degraded["collection"]["issues"])
        @test degraded["collection"]["status"] === :partial
        @test :r_version in issue_stages
        @test :git_root in issue_stages
        @test !degraded["git"]["available"]
    end
end
