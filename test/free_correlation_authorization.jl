using BayesianMGMFRM
using Test

const _bind_free_correlation_authorization = getfield(
    BayesianMGMFRM,
    :_free_correlation_study_bind_evaluation_authorization,
)

@testset "free-correlation authorization fails closed" begin
    feasibility_sha256 = repeat("a", 64)
    decision_fingerprint = repeat("b", 64)
    authorization = (;
        evaluation_execution_authorized = true,
        protocol_integrity_evidence = (; passed = true),
        feasibility_result_set_sha256 = feasibility_sha256,
        decision_fingerprint,
    )

    @test _bind_free_correlation_authorization(
        authorization,
        feasibility_sha256,
        decision_fingerprint,
    ) === authorization

    @test_throws ArgumentError _bind_free_correlation_authorization(
        merge(authorization, (; evaluation_execution_authorized = false)),
        feasibility_sha256,
        decision_fingerprint,
    )
    @test_throws ArgumentError _bind_free_correlation_authorization(
        merge(authorization, (;
            protocol_integrity_evidence = (; passed = false),
        )),
        feasibility_sha256,
        decision_fingerprint,
    )
    @test_throws ArgumentError _bind_free_correlation_authorization(
        authorization,
        repeat("c", 64),
        decision_fingerprint,
    )
    @test_throws ArgumentError _bind_free_correlation_authorization(
        authorization,
        feasibility_sha256,
        repeat("d", 64),
    )
end
