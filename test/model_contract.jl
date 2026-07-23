using Test
using BayesianMGMFRM
using LogDensityProblems

function _model_contract_fixture(; thresholds = :partial_credit)
    table = (
        examinee = ["E1", "E1", "E1", "E2", "E2", "E2", "E3", "E3", "E3"],
        rater = ["R1", "R2", "R1", "R1", "R2", "R1", "R1", "R2", "R1"],
        item = ["I1", "I1", "I2", "I1", "I2", "I2", "I1", "I2", "I2"],
        score = [0, 1, 2, 1, 0, 2, 1, 2, 0],
    )
    data = FacetData(
        table;
        person = :examinee,
        rater = :rater,
        item = :item,
        score = :score,
    )
    spec = mfrm_spec(data; thresholds)
    design = getdesign(spec)
    return (; data, spec, design)
end

@testset "canonical model contract and execution snapshots" begin
    fixture = _model_contract_fixture()
    identity = design_identity(fixture.design)
    @test identity.schema == "bayesianmgmfrm.design_identity.v1"
    @test identity.algorithm === :sha256
    @test length(identity.value) == 64
    @test identity.canonical
    @test identity.snapshot_policy ===
        :validated_deepcopy_at_numerical_entry
    @test design_identity(deepcopy(fixture.design)).value == identity.value
    @test design_identity(getdesign(fixture.spec)).value == identity.value
    @test model_manifest(fixture.design).design_identity.value == identity.value

    rating_scale = _model_contract_fixture(; thresholds = :rating_scale)
    @test design_identity(rating_scale.design).value != identity.value

    forged_names = FacetDesign(
        fixture.spec,
        reverse(copy(fixture.design.parameter_names)),
        copy(fixture.design.blocks),
        copy(fixture.design.identification),
    )
    @test_throws ArgumentError design_identity(forged_names)
    @test_throws ArgumentError fit(
        forged_names;
        ndraws = 1,
        warmup = 0,
        seed = 101,
    )

    forged_identification = FacetDesign(
        fixture.spec,
        copy(fixture.design.parameter_names),
        copy(fixture.design.blocks),
        merge(copy(fixture.design.identification),
            Dict(:rater => :sum_to_zero)),
    )
    @test_throws ArgumentError design_identity(forged_identification)

    stale_data_fixture = _model_contract_fixture()
    stale_data_fixture.data.category[1] = 2
    @test_throws ArgumentError getdesign(stale_data_fixture.spec)
    @test_throws ArgumentError design_identity(stale_data_fixture.design)
    @test_throws ArgumentError loglikelihood(
        stale_data_fixture.design,
        zeros(length(stale_data_fixture.design.parameter_names)),
    )
    @test_throws ArgumentError fit_cache_key(
        stale_data_fixture.design;
        seed = 102,
    )

    stale_spec_fixture = _model_contract_fixture()
    push!(stale_spec_fixture.spec.dimension_labels, "forged")
    @test_throws ArgumentError getdesign(stale_spec_fixture.spec)

    snapshot_fixture = _model_contract_fixture()
    target = MFRMLogDensity(snapshot_fixture.design)
    @test target.design !== snapshot_fixture.design
    target_identity = design_identity(target.design).value
    target_logdensity = LogDensityProblems.logdensity(
        target,
        zeros(length(target.design.parameter_names)),
    )
    snapshot_fixture.data.score[1] = 1
    @test_throws ArgumentError design_identity(snapshot_fixture.design)
    @test design_identity(target.design).value == target_identity
    @test LogDensityProblems.logdensity(
        target,
        zeros(length(target.design.parameter_names)),
    ) == target_logdensity

    fit_fixture = _model_contract_fixture()
    result = fit(
        fit_fixture.design;
        ndraws = 2,
        warmup = 0,
        chains = 1,
        seed = 103,
    )
    @test result.design !== fit_fixture.design
    fit_identity = design_identity(result.design).value
    @test fit_metadata(result).design_identity.value == fit_identity
    fit_fixture.data.category[1] = 2
    @test_throws ArgumentError design_identity(fit_fixture.design)
    @test design_identity(result.design).value == fit_identity

    result.design.parameter_names[1] = "forged_after_fit"
    @test_throws ArgumentError fit_metadata(result)
    @test_throws ArgumentError model_manifest(result.design)
end
