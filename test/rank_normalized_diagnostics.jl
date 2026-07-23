function _rank_diagnostic_oracle_draws(n::Int; nchains::Int = 4)
    values = Array{Float64}(undef, n, nchains, 1)
    for chain in 1:nchains, iteration in 1:n
        values[iteration, chain, 1] =
            sin(0.37 * iteration + 0.11 * chain) +
            0.03 * chain * iteration / n
    end
    return values
end

function _rank_diagnostic_scale_pathology_draws()
    values = Array{Float64}(undef, 80, 4, 1)
    scales = (0.1, 1.0, 10.0, 100.0)
    for chain in 1:4, iteration in 1:80
        values[iteration, chain, 1] =
            (sin(0.51 * iteration) + cos(0.13 * iteration)) * scales[chain]
    end
    return values
end

function _rank_diagnostic_long_autocorrelation_draws()
    values = Array{Float64}(undef, 1_200, 4, 1)
    for chain in 1:4, iteration in 1:1_200
        values[iteration, chain, 1] =
            sin(0.003 * iteration + 0.17 * chain) +
            0.0002 * chain * iteration
    end
    return values
end

function _rank_diagnostic_draw_matrix(values::Array{Float64,3})
    niterations, nchains, nparams = size(values)
    draws = Matrix{Float64}(undef, niterations * nchains, nparams)
    for chain in 1:nchains
        rows = ((chain - 1) * niterations + 1):(chain * niterations)
        draws[rows, :] .= values[:, chain, :]
    end
    return draws
end

@testset "rank-normalized R-hat and bulk/tail ESS oracle" begin
    # These reference values were independently evaluated with posterior 1.7.0.
    # The odd-length case verifies posterior/Stan center-draw removal semantics.
    oracle_cases = (
        (;
            n = 40,
            bulk_rhat = 0.98103201636587523,
            folded_rhat = 0.97512810570375219,
            rank_rhat = 0.98103201636587523,
            bulk_ess = 39.08160806518255,
            tail_ess = 96.98932155569574,
        ),
        (;
            n = 41,
            bulk_rhat = 0.97813926283152186,
            folded_rhat = 0.97755037709810011,
            rank_rhat = 0.97813926283152186,
            bulk_ess = 38.11003174513060,
            tail_ess = 90.86717432309702,
        ),
    )
    for oracle in oracle_cases
        result = BayesianMGMFRM._rank_normalized_rhat_bulk_tail_ess(
            _rank_diagnostic_oracle_draws(oracle.n),
            1;
            split_chains = true,
        )
        @test result.flag === :ok
        @test result.bulk_rank_normalized_rhat ≈ oracle.bulk_rhat atol = 1e-10 rtol = 1e-10
        @test result.folded_rank_normalized_rhat ≈ oracle.folded_rhat atol = 1e-10 rtol = 1e-10
        @test result.rank_normalized_rhat ≈ oracle.rank_rhat atol = 1e-10 rtol = 1e-10
        @test result.bulk_ess ≈ oracle.bulk_ess atol = 1e-10 rtol = 1e-10
        @test result.tail_ess ≈ oracle.tail_ess atol = 1e-10 rtol = 1e-10
        @test result.tail_probability == 0.10
        @test result.autocovariance_maxlag == div(oracle.n, 2) - 4
    end

    scale_result = BayesianMGMFRM._rank_normalized_rhat_bulk_tail_ess(
        _rank_diagnostic_scale_pathology_draws(),
        1;
        split_chains = true,
    )
    @test scale_result.flag === :ok
    @test scale_result.bulk_rank_normalized_rhat ≈ 0.99215519693309095 atol = 1e-10 rtol = 1e-10
    @test scale_result.folded_rank_normalized_rhat ≈ 1.9795993280041468 atol = 1e-10 rtol = 1e-10
    @test scale_result.rank_normalized_rhat ≈ 1.9795993280041468 atol = 1e-10 rtol = 1e-10
    @test scale_result.bulk_ess ≈ 75.88807117919188 atol = 1e-10 rtol = 1e-10
    @test scale_result.tail_ess ≈ 35.98275622305662 atol = 1e-10 rtol = 1e-10

    long_result = BayesianMGMFRM._rank_normalized_rhat_bulk_tail_ess(
        _rank_diagnostic_long_autocorrelation_draws(),
        1;
        split_chains = true,
    )
    @test long_result.flag === :ok
    @test long_result.bulk_rank_normalized_rhat ≈ 1.4298914894477248 atol = 1e-10 rtol = 1e-10
    @test long_result.folded_rank_normalized_rhat ≈ 1.0328791192279514 atol = 1e-10 rtol = 1e-10
    @test long_result.rank_normalized_rhat ≈ 1.4298914894477248 atol = 1e-10 rtol = 1e-10
    @test long_result.bulk_ess ≈ 8.269374479336422 atol = 1e-10 rtol = 1e-10
    @test long_result.tail_ess ≈ 27.01079727947117 atol = 1e-10 rtol = 1e-10
    @test long_result.autocovariance_maxlag == 596
end

@testset "rank-normalized diagnostic boundaries and invariance" begin
    for n in (1, 4, 5, 9, 10), split_chains in (true, false)
        one_chain = BayesianMGMFRM._rank_normalized_rhat_bulk_tail_ess(
            _rank_diagnostic_oracle_draws(n; nchains = 1),
            1;
            split_chains,
        )
        @test one_chain.flag === :insufficient_chains
        @test all(isnan, (
            one_chain.rank_normalized_rhat,
            one_chain.bulk_rank_normalized_rhat,
            one_chain.folded_rank_normalized_rhat,
            one_chain.bulk_ess,
            one_chain.tail_ess,
        ))
    end

    expected_flags = Dict(
        (1, true) => :insufficient_draws,
        (1, false) => :insufficient_draws,
        (4, true) => :insufficient_draws,
        (4, false) => :insufficient_draws,
        (5, true) => :insufficient_draws,
        (5, false) => :ok,
        (9, true) => :insufficient_draws,
        (9, false) => :ok,
        (10, true) => :ok,
        (10, false) => :ok,
    )
    for ((n, split_chains), expected_flag) in expected_flags
        result = BayesianMGMFRM._rank_normalized_rhat_bulk_tail_ess(
            _rank_diagnostic_oracle_draws(n),
            1;
            split_chains,
        )
        @test result.flag === expected_flag
        if expected_flag === :ok
            diagnostic_iterations = split_chains ? div(n, 2) : n
            @test result.autocovariance_maxlag == diagnostic_iterations - 4
            @test all(isfinite, (
                result.rank_normalized_rhat,
                result.bulk_ess,
                result.tail_ess,
            ))
        else
            @test isnan(result.bulk_ess)
            @test isnan(result.tail_ess)
            @test ismissing(result.autocovariance_maxlag)
        end
    end

    for bad_value in (NaN, Inf, -Inf)
        contaminated = _rank_diagnostic_oracle_draws(40)
        contaminated[7, 2, 1] = bad_value
        result = BayesianMGMFRM._rank_normalized_rhat_bulk_tail_ess(
            contaminated,
            1;
            split_chains = true,
        )
        @test result.flag === :nonfinite_draws
        @test all(isnan, (
            result.rank_normalized_rhat,
            result.bulk_rank_normalized_rhat,
            result.folded_rank_normalized_rhat,
            result.bulk_ess,
            result.tail_ess,
        ))
    end

    constant_result = BayesianMGMFRM._rank_normalized_rhat_bulk_tail_ess(
        fill(2.5, 40, 4, 1),
        1;
        split_chains = true,
    )
    @test constant_result.flag === :degenerate_draws
    @test all(isnan, (
        constant_result.rank_normalized_rhat,
        constant_result.bulk_rank_normalized_rhat,
        constant_result.folded_rank_normalized_rhat,
        constant_result.bulk_ess,
        constant_result.tail_ess,
    ))

    base_values = _rank_diagnostic_oracle_draws(40)
    base = BayesianMGMFRM._rank_normalized_rhat_bulk_tail_ess(
        base_values,
        1;
        split_chains = true,
    )
    transformed = BayesianMGMFRM._rank_normalized_rhat_bulk_tail_ess(
        exp.(base_values),
        1;
        split_chains = true,
    )
    @test transformed.bulk_rank_normalized_rhat ≈ base.bulk_rank_normalized_rhat atol = 1e-12 rtol = 1e-12
    @test transformed.rank_normalized_rhat ≈ base.rank_normalized_rhat atol = 1e-12 rtol = 1e-12
    @test transformed.bulk_ess ≈ base.bulk_ess atol = 1e-12 rtol = 1e-12
    @test transformed.tail_ess ≈ base.tail_ess atol = 1e-12 rtol = 1e-12

    permuted = BayesianMGMFRM._rank_normalized_rhat_bulk_tail_ess(
        base_values[:, [4, 2, 1, 3], :],
        1;
        split_chains = true,
    )
    for field in (
            :rank_normalized_rhat,
            :bulk_rank_normalized_rhat,
            :folded_rank_normalized_rhat,
            :bulk_ess,
            :tail_ess)
        @test getproperty(permuted, field) ≈ getproperty(base, field) atol = 1e-12 rtol = 1e-12
    end
end

@testset "modern primary flag and classical compatibility flag" begin
    values = _rank_diagnostic_scale_pathology_draws()
    metrics = BayesianMGMFRM._mcmc_parameter_metrics(
        values,
        1;
        split_chains = true,
    )
    @test metrics.rank_normalized_rhat > 1.1
    @test metrics.rhat < 1.1
    @test BayesianMGMFRM._mcmc_parameter_flag(metrics, 1.1, 1.0) ===
        :mcmc_warning
    @test BayesianMGMFRM._classical_compatibility_parameter_flag(
        metrics,
        1.1,
        1.0,
    ) === :ok

    rows = BayesianMGMFRM._candidate_mcmc_diagnostic_rows(
        _rank_diagnostic_draw_matrix(values),
        ["scale_pathology"],
        4;
        parameter_space = :raw_unconstrained,
        split_chains = true,
        rhat_threshold = 1.1,
        ess_threshold = 1.0,
    )
    row = only(rows)
    @test row.diagnostic_contract ===
        :rank_normalized_rhat_bulk_tail_ess_v1
    @test row.diagnostic_method ===
        :rank_normalized_split_rhat_bulk_tail_ess
    @test row.diagnostic_status === :rank_normalized_available
    @test row.quality_gate_applicable
    @test row.split_chains_requested
    @test row.flag === row.rank_normalized_flag === :mcmc_warning
    @test row.classical_compatibility_flag === :ok
    @test row.rank_normalized_rhat == max(
        row.bulk_rank_normalized_rhat,
        row.folded_rank_normalized_rhat,
    )

    unsplit_row = only(BayesianMGMFRM._candidate_mcmc_diagnostic_rows(
        _rank_diagnostic_draw_matrix(_rank_diagnostic_oracle_draws(10)),
        ["unsplit"],
        4;
        parameter_space = :raw_unconstrained,
        split_chains = false,
        rhat_threshold = 1.1,
        ess_threshold = 1.0,
    ))
    @test unsplit_row.diagnostic_method ===
        :rank_normalized_unsplit_rhat_bulk_tail_ess
    @test !unsplit_row.split_chains_requested
    @test !unsplit_row.split_chains
end

@testset "structurally fixed generalized coordinates" begin
    data = FacetData((;
        person = ["P1", "P1", "P2", "P2"],
        rater = ["R1", "R2", "R1", "R2"],
        item = fill("I1", 4),
        score = [0, 1, 1, 2],
    ); person = :person, rater = :rater, item = :item, score = :score)
    spec = mfrm_spec(
        data;
        family = :gmfrm,
        thresholds = :partial_credit,
        discrimination = :rater,
    )
    design = getdesign(spec; preview = true)
    blueprint = BayesianMGMFRM._gmfrm_source_unconstrained_blueprint(design)
    fixed = BayesianMGMFRM._structurally_fixed_constrained_parameter_names(
        blueprint,
    )
    @test fixed == Set([
        "item[I1]",
        "item_discrimination[item=I1]",
    ])

    niterations = 10
    nchains = 4
    nparameters = length(blueprint.constrained_parameter_names)
    direct_draws = Matrix{Float64}(
        undef,
        niterations * nchains,
        nparameters,
    )
    for chain in 1:nchains, iteration in 1:niterations
        row = (chain - 1) * niterations + iteration
        for parameter in 1:nparameters
            direct_draws[row, parameter] =
                sin(0.31 * iteration + 0.17 * chain + 0.07 * parameter)
        end
    end
    direct_draws[:, findfirst(==("item[I1]"),
        blueprint.constrained_parameter_names)] .= 0.0
    direct_draws[:, findfirst(==("item_discrimination[item=I1]"),
        blueprint.constrained_parameter_names)] .= 1.0

    rows = BayesianMGMFRM._candidate_mcmc_diagnostic_rows(
        direct_draws,
        blueprint.constrained_parameter_names,
        nchains;
        parameter_space = :direct_constrained,
        structurally_fixed_parameters = fixed,
        split_chains = true,
        rhat_threshold = 1.01,
        ess_threshold = 400.0,
    )
    fixed_rows = filter(row -> row.parameter in fixed, rows)
    @test length(fixed_rows) == 2
    @test all(row -> !row.quality_gate_applicable &&
        row.diagnostic_status === :structurally_fixed &&
        row.rank_normalized_flag === :structurally_fixed &&
        row.classical_compatibility_flag === :structurally_fixed &&
        row.flag === :structurally_fixed,
        fixed_rows)
    @test all(row -> all(isnan, (
            row.rank_normalized_rhat,
            row.bulk_ess,
            row.tail_ess,
        )), fixed_rows)

    block_rows = BayesianMGMFRM._candidate_parameter_block_diagnostics(
        blueprint.constrained_blocks,
        blueprint.constrained_parameter_names,
        rows;
        parameter_space = :direct_constrained,
        chains = nchains,
        draws_per_chain = niterations,
        total_draws = niterations * nchains,
        split_chains = true,
        split_chains_requested = true,
        rhat_threshold = 1.01,
        ess_threshold = 400.0,
    )
    fixed_blocks = filter(row -> row.block in
        (:item, :item_discrimination), block_rows)
    @test length(fixed_blocks) == 2
    @test all(row -> row.diagnostic_status === :structurally_fixed &&
        !row.quality_gate_applicable &&
        row.n_quality_gate_parameters == 0 &&
        row.n_structurally_fixed_parameters == 1 &&
        row.rank_normalized_flag === :structurally_fixed &&
        row.classical_compatibility_flag === :structurally_fixed,
        fixed_blocks)

    metrics = BayesianMGMFRM._mcmc_metric_summary(
        rows,
        1.01,
        400.0,
    )
    @test metrics.n_parameters == nparameters
    @test metrics.n_quality_gate_parameters == nparameters - 2
    @test metrics.n_structurally_fixed_parameters == 2
    @test metrics.n_degenerate_parameters == 0
end

@testset "modern diagnostic policy and fit-cache identity" begin
    policy = BayesianMGMFRM._diagnostic_row_policy(
        family = :mfrm,
        parameter_spaces = (:identified,),
    )
    @test policy.diagnostic_contract ===
        :rank_normalized_rhat_bulk_tail_ess_v1
    @test policy.diagnostic_contract_details.id === policy.diagnostic_contract
    @test policy.diagnostic_contract_details.diagnostic_methods.split ===
        :rank_normalized_split_rhat_bulk_tail_ess
    @test policy.diagnostic_contract_details.diagnostic_methods.unsplit ===
        :rank_normalized_unsplit_rhat_bulk_tail_ess
    @test policy.diagnostic_contract_details.quality_gate.applicability_field ===
        :quality_gate_applicable
    @test policy.diagnostic_contract_details.quality_gate.structurally_fixed_status ===
        :structurally_fixed
    @test policy.rhat_method === :rank_normalized
    @test policy.rhat_components == (
        :bulk_rank_normalized_rhat,
        :folded_rank_normalized_rhat,
    )
    @test policy.primary_rhat_field === :rank_normalized_rhat
    @test policy.ess_method === :bulk_and_tail
    @test policy.primary_ess_fields == (:bulk_ess, :tail_ess)
    @test policy.tail_probability == 0.10
    @test policy.autocovariance_maxlag_policy === :all_available_lags
    @test policy.minimum_draws_per_diagnostic_chain_for_ess == 5
    @test policy.compatibility_rhat_field === :rhat
    @test policy.compatibility_rhat_method === :classical_split
    @test policy.compatibility_ess_field === :ess
    @test policy.compatibility_ess_method === :autocorrelation
    @test policy.primary_flag_field === :rank_normalized_flag
    @test policy.compatibility_flag_field === :classical_compatibility_flag
    @test policy.rhat_ess_status === :rank_normalized_available
    @test policy.rank_normalized_rhat_available
    @test policy.bulk_tail_ess_available
    @test :insufficient_draws in policy.failure_flags
    @test :nonfinite_draws in policy.failure_flags
    @test :direct_transform_warning in policy.failure_flags
    @test isempty(intersect(
        Set(policy.informational_flags),
        Set(policy.failure_flags),
    ))
    @test !hasproperty(policy, :next_gate)
    for invalid_rhat in (NaN, Inf, -Inf)
        @test_throws ArgumentError BayesianMGMFRM._check_diagnostic_thresholds(
            invalid_rhat,
            400.0,
        )
    end
    for invalid_ess in (NaN, Inf, -Inf)
        @test_throws ArgumentError BayesianMGMFRM._check_diagnostic_thresholds(
            1.01,
            invalid_ess,
        )
    end

    data = FacetData((;
        person = ["P1", "P1", "P1", "P2", "P2", "P2"],
        rater = ["R1", "R2", "R1", "R1", "R2", "R1"],
        item = ["I1", "I1", "I2", "I1", "I2", "I2"],
        score = [0, 1, 2, 1, 0, 2],
    ); person = :person, rater = :rater, item = :item, score = :score)
    design = getdesign(mfrm_spec(data))
    request = BayesianMGMFRM._fit_cache_request(
        design;
        ndraws = 10,
        warmup = 0,
        chains = 2,
        seed = 20260720,
    )
    cache_key = fit_cache_key(
        design;
        ndraws = 10,
        warmup = 0,
        chains = 2,
        seed = 20260720,
    )
    @test request.diagnostic_contract == policy.diagnostic_contract_details
    @test cache_key == BayesianMGMFRM._cache_hash(request)
    legacy_request = merge(request, (;
        diagnostic_contract = merge(
            request.diagnostic_contract,
            (; id = :classical_split_rhat_autocorrelation_ess_v0),
        ),
    ))
    @test BayesianMGMFRM._cache_hash(legacy_request) != cache_key
    legacy_surface = (;
        summary = (; diagnostic_contract =
            :classical_split_rhat_autocorrelation_ess_v0),
    )
    @test_throws ArgumentError BayesianMGMFRM._check_stored_generalized_diagnostic_contract(
        legacy_surface,
        "test generalized",
    )
    incomplete_surface = (;
        summary = (;
            diagnostic_contract = policy.diagnostic_contract,
            diagnostic_contract_details = policy.diagnostic_contract_details,
        ),
        parameter_rows = NamedTuple[],
        direct_parameter_rows = NamedTuple[],
        block_rows = NamedTuple[],
        direct_block_rows = [(; diagnostic_contract =
            policy.diagnostic_contract)],
    )
    @test_throws ArgumentError BayesianMGMFRM._check_stored_generalized_diagnostic_contract(
        incomplete_surface,
        "test generalized",
    )
end

@testset "E-BFMI coverage is explicit" begin
    complete = BayesianMGMFRM._ebfmi_coverage([
        (; e_bfmi = 0.71),
        (; e_bfmi = 0.42),
        (; e_bfmi = 0.63),
    ])
    @test complete.e_bfmi == 0.42
    @test complete.n_e_bfmi_expected == 3
    @test complete.n_e_bfmi_available == 3
    @test complete.n_e_bfmi_unavailable == 0
    @test complete.e_bfmi_complete

    incomplete = BayesianMGMFRM._ebfmi_coverage([
        (; e_bfmi = 0.71),
        (; e_bfmi = missing),
        (; e_bfmi = 0.63),
    ])
    @test incomplete.e_bfmi == 0.63
    @test incomplete.n_e_bfmi_expected == 3
    @test incomplete.n_e_bfmi_available == 2
    @test incomplete.n_e_bfmi_unavailable == 1
    @test !incomplete.e_bfmi_complete

    @test isfinite(BayesianMGMFRM._ebfmi([1.0, 2.0, 4.0, 3.0]))
    @test ismissing(BayesianMGMFRM._ebfmi([1.0, 2.0, missing, 3.0]))
    @test ismissing(BayesianMGMFRM._ebfmi([1.0, 2.0, NaN, 3.0]))
    @test ismissing(BayesianMGMFRM._ebfmi([2.0, 2.0, 2.0]))
end

module PublicationGradeRefitRunnerDiagnosticContractForTest

include(joinpath(@__DIR__, "..", "scripts",
    "run_mgmfrm_publication_grade_refit_job.jl"))

end


@testset "publication-grade runner uses the modern diagnostic contract" begin
    runner = PublicationGradeRefitRunnerDiagnosticContractForTest
    contract = :rank_normalized_rhat_bulk_tail_ess_v1
    score_row = (;
        chains = 4,
        warmup = 1_000,
        draws_per_chain = 2_000,
        modern_diagnostic_metrics_complete = true,
        diagnostic_contract = contract,
        # Compatibility values deliberately disagree with the primary values.
        max_rhat = 9.9,
        min_ess = 2.0,
        max_rank_normalized_rhat = 1.004,
        min_bulk_ess = 812.0,
        min_tail_ess = 703.0,
        n_divergences = 0,
        n_max_treedepth = 0,
        e_bfmi = 0.75,
        e_bfmi_complete = true,
        all_pointwise_scores_finite = true,
        posterior_predictive_check_recorded = true,
        expected_score_residuals_finite = true,
    )
    @test runner.diagnostic_value(:rank_normalized_rhat_max, score_row) ==
        score_row.max_rank_normalized_rhat
    @test runner.diagnostic_value(:ess_bulk_min, score_row) ==
        score_row.min_bulk_ess
    @test runner.diagnostic_value(:ess_tail_min, score_row) ==
        score_row.min_tail_ess
    @test runner.diagnostic_value(:ebfmi_min, score_row) ==
        score_row.e_bfmi
    @test runner.diagnostic_value(:rank_normalized_rhat_max, score_row) !=
        score_row.max_rhat
    @test runner.diagnostic_value(:ess_bulk_min, score_row) !=
        score_row.min_ess

    incomplete_score = merge(score_row, (;
        modern_diagnostic_metrics_complete = false,
    ))
    @test ismissing(runner.diagnostic_value(
        :rank_normalized_rhat_max,
        incomplete_score,
    ))
    @test ismissing(runner.diagnostic_value(:ess_bulk_min, incomplete_score))
    @test ismissing(runner.diagnostic_value(:ess_tail_min, incomplete_score))
    incomplete_ebfmi_score = merge(score_row, (; e_bfmi_complete = false))
    @test ismissing(runner.diagnostic_value(
        :ebfmi_min,
        incomplete_ebfmi_score,
    ))
    @test ismissing(runner.diagnostic_value(
        :ebfmi_min,
        (; e_bfmi = 0.75),
    ))
    wrong_contract_score = merge(score_row, (;
        diagnostic_contract = :pre_modern_diagnostic_contract,
    ))
    @test ismissing(runner.diagnostic_value(
        :rank_normalized_rhat_max,
        wrong_contract_score,
    ))
    @test ismissing(runner.diagnostic_value(
        :ebfmi_min,
        wrong_contract_score,
    ))
    @test ismissing(runner.diagnostic_value(
        :rank_normalized_rhat_max,
        (;
            modern_diagnostic_metrics_complete = true,
            max_rank_normalized_rhat = 1.0,
        ),
    ))

    gate = (;
        diagnostic_gate_rows = [
            (;
                diagnostic = String(diagnostic),
                source = "fit_diagnostics",
                comparison = diagnostic === :rank_normalized_rhat_max ?
                    "less_or_equal" : "greater_or_equal",
                threshold = diagnostic === :rank_normalized_rhat_max ?
                    1.01 : 400.0,
                public_claim_blocked_if_missing = true,
            )
            for diagnostic in (
                :rank_normalized_rhat_max,
                :ess_bulk_min,
                :ess_tail_min,
            )
        ],
    )
    unit = (;
        execution_unit_id = "modern-diagnostic-contract-test",
        scenario = :unit_test,
        model = :confirmatory_mgmfrm_current_q,
        fold = 1,
        mcmc_refit_required = true,
    )
    rows = runner.diagnostic_rows(gate, unit, score_row, false)
    @test length(rows) == 3
    @test all(row -> row.diagnostic_contract === contract, rows)
    @test all(row -> row.diagnostic_contract_required &&
        row.diagnostic_contract_matches_requirement, rows)
    @test all(row -> row.applicable && row.observed && row.passed, rows)
    @test Dict(row.diagnostic => row.value for row in rows) == Dict(
        :rank_normalized_rhat_max => score_row.max_rank_normalized_rhat,
        :ess_bulk_min => score_row.min_bulk_ess,
        :ess_tail_min => score_row.min_tail_ess,
    )

    wrong_contract_rows = runner.diagnostic_rows(
        gate,
        unit,
        wrong_contract_score,
        false,
    )
    @test all(row -> row.observed &&
        row.diagnostic_contract_required &&
        !row.diagnostic_contract_matches_requirement &&
        ismissing(row.value) &&
        !row.passed, wrong_contract_rows)
end
