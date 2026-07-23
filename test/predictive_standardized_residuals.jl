using Test
using BayesianMGMFRM

function _psr_fixture_data()
    table = (;
        person = ["E1", "E1", "E1", "E2", "E2", "E2"],
        rater = ["R1", "R2", "R1", "R1", "R2", "R1"],
        item = ["I1", "I1", "I2", "I1", "I2", "I2"],
        score = [0, 1, 2, 1, 0, 2],
    )
    return FacetData(
        table;
        person = :person,
        rater = :rater,
        item = :item,
        score = :score,
    )
end

function _psr_fixture_raw_draws(target)
    n_parameters = length(initial_params(target))
    draws = zeros(2, n_parameters)
    draws[2, :] .= range(-0.12, 0.12; length = n_parameters)
    return draws
end

function _psr_mfrm_fixture(data)
    design = getdesign(mfrm_spec(data; thresholds = :partial_credit))
    draws = zeros(2, length(design.parameter_names))
    draws[2, :] .= range(-0.12, 0.12; length = size(draws, 2))
    return MFRMFit(
        design,
        MFRMPrior(),
        draws,
        zeros(2),
        1.0,
        [1, 1],
        [1, 2],
        [1.0],
        :fixture,
        :fixture,
        0,
        0.1,
    )
end

function _psr_gmfrm_fixture(data)
    spec = mfrm_spec(
        data;
        family = :gmfrm,
        discrimination = :rater,
        thresholds = :partial_credit,
    )
    design = getdesign(spec; preview = true)
    prior = BayesianMGMFRM._SourceFixturePrior()
    target = BayesianMGMFRM._gmfrm_promotion_candidate_logdensity(
        design;
        prior,
    )
    raw_draws = _psr_fixture_raw_draws(target)
    direct = BayesianMGMFRM._gmfrm_candidate_direct_draw_values(
        target,
        raw_draws,
    )
    return GMFRMFit(
        design,
        prior,
        raw_draws,
        zeros(2),
        direct.direct_draws,
        direct.loglikelihood,
        direct.pointwise_loglikelihood,
        [1, 1],
        [1, 2],
        [1.0],
        :fixture,
        :fixture,
        0,
        0.1,
        NamedTuple[],
        (;),
        (;),
    )
end

function _psr_mgmfrm_fixture(data)
    spec = mfrm_spec(
        data;
        family = :mgmfrm,
        dimensions = 2,
        q_matrix = Bool[1 0; 0 1],
        thresholds = :partial_credit,
    )
    design = getdesign(spec; preview = true)
    prior = BayesianMGMFRM._SourceFixturePrior()
    target = BayesianMGMFRM._mgmfrm_guarded_local_fit_logdensity(
        design;
        prior,
    )
    raw_draws = _psr_fixture_raw_draws(target)
    direct = BayesianMGMFRM._mgmfrm_guarded_local_fit_direct_draw_values(
        target,
        raw_draws,
    )
    return MGMFRMFit(
        design,
        prior,
        raw_draws,
        zeros(2),
        direct.direct_draws,
        direct.loglikelihood,
        direct.pointwise_loglikelihood,
        [1, 1],
        [1, 2],
        [1.0],
        :fixture,
        :fixture,
        0,
        0.1,
        NamedTuple[],
        (;),
        (;),
    )
end

function _test_psr_family(fit, family::Symbol)
    indices = [2, 1]
    residuals = predictive_residuals(fit; draw_indices = indices)
    variances = predictive_variances(fit; draw_indices = indices)
    manual = residuals ./ sqrt.(variances)

    result = predictive_standardized_residuals(
        fit;
        draw_indices = indices,
        variance_tolerance = 0.0,
    )
    @test result.family === family
    @test result.draw_indices == (2, 1)
    @test result.nonfinite_prediction_action === :error
    @test all(result.valid)
    @test result.values ≈ manual
    @test result.n_valid == length(result.valid)
    @test result.n_excluded == 0

    boundary = variances[1, 1]
    expected_valid = variances .> boundary
    masked = predictive_standardized_residuals(
        fit;
        draw_indices = indices,
        variance_tolerance = boundary,
    )
    @test !masked.valid[1, 1]
    @test masked.valid == expected_valid
    @test masked.n_valid == count(expected_valid)
    @test masked.n_excluded == length(expected_valid) - count(expected_valid)
    @test masked.excluded_by_draw == Tuple(
        count(!, @view expected_valid[draw, :])
        for draw in axes(expected_valid, 1)
    )
    @test masked.excluded_by_observation == Tuple(
        count(!, @view expected_valid[:, row])
        for row in axes(expected_valid, 2)
    )
    @test all(isnan, masked.values[.!expected_valid])
    @test masked.values[expected_valid] ≈ manual[expected_valid]
end

@testset "predictive standardized residual family equivalence" begin
    data = _psr_fixture_data()
    for (fit, family) in (
            (_psr_mfrm_fixture(data), :mfrm),
            (_psr_gmfrm_fixture(data), :gmfrm),
            (_psr_mgmfrm_fixture(data), :mgmfrm),
        )
        _test_psr_family(fit, family)
    end
end

@testset "predictive standardized residual non-finite predictions" begin
    data = _psr_fixture_data()
    fit = _psr_mfrm_fixture(data)
    design = fit.design

    for value in (NaN, Inf, -Inf)
        draws = copy(fit.draws)
        draws[1, 1] = value
        exception = try
            predictive_standardized_residuals(design, draws)
            nothing
        catch caught
            caught
        end
        @test exception isa ArgumentError
        if exception isa ArgumentError
            @test occursin("non-finite", sprint(showerror, exception))
        end
    end

    @test_throws ArgumentError predictive_standardized_residuals(
        design,
        fit.draws;
        variance_tolerance = NaN,
    )
    @test_throws ArgumentError predictive_standardized_residuals(
        design,
        fit.draws;
        variance_tolerance = Inf,
    )
end
