module FullPaperReproductionArchiveContractForTest

include(joinpath(@__DIR__, "..", "scripts",
    "generate_gmfrm_full_paper_reproduction_archive.jl"))

end

@testset "full archive guarded-summary contract" begin
    generator = FullPaperReproductionArchiveContractForTest
    spec = (;
        name = :guarded_exposure_review,
        pass_policy = :summary_passed,
    )
    @test generator.summary_passed(
        spec,
        "{\"reviewed\":true,\"all_local_evidence_passed\":true}",
    )
    @test !generator.summary_passed(
        spec,
        "{\"passed\":true,\"reviewed\":true," *
        "\"all_local_evidence_passed\":false}",
    )
    @test !generator.summary_passed(
        spec,
        "{\"reviewed\":true}",
    )
end
