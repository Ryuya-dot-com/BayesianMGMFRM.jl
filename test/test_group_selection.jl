using Test

if !isdefined(@__MODULE__, :test_group_enabled)
    include("test_groups.jl")
end

@testset "ordinary test-shard selection" begin
    @test selected_test_group("") === :all
    @test selected_test_group(" ALL ") === :all
    @test selected_test_group(" FITTING_REPORTS "; research_evidence = false) ===
        :fitting_reports
    @test_throws ArgumentError selected_test_group("misspelled")
    @test_throws ArgumentError test_group_enabled(:misspelled, :all)

    workflow = read(joinpath(@__DIR__, "..", ".github", "workflows", "CI.yml"), String)
    ci_groups = Tuple(Symbol(m.captures[1]) for m in
        eachmatch(r"(?m)^\s*- group: (\w+)\s*$", workflow))
    @test ci_groups == TEST_SHARDS

    for group in TEST_GROUPS
        @test selected_test_group(string(group); research_evidence = false) === group
        @test_throws ArgumentError selected_test_group(
            string(group); research_evidence = true)
    end
    @test selected_test_group("all"; research_evidence = true) === :all

    for shard in TEST_SHARDS
        @test test_group_enabled(shard, :all)
        @test count(active -> test_group_enabled(shard, active), TEST_SHARDS) == 1
        @test test_group_enabled(shard, shard)
    end
    @test filter(shard -> test_group_enabled(shard, :fitting), TEST_SHARDS) ==
        (:fitting_core, :fitting_reports)
    @test filter(shard -> test_group_enabled(shard, :local_dependence), TEST_SHARDS) ==
        (:local_dependence_core, :local_dependence_integrity)

    withenv("BAYESIANMGMFRM_TEST_GROUP" => "local_dependence_integrity") do
        @test selected_test_group(; research_evidence = false) ===
            :local_dependence_integrity
    end
    withenv("BAYESIANMGMFRM_RESEARCH_EVIDENCE_TESTS" => "misspelled") do
        @test_throws ArgumentError test_flag("BAYESIANMGMFRM_RESEARCH_EVIDENCE_TESTS")
    end
end
