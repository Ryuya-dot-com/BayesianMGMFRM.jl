function check_gmfrm_candidate_chain_study_fixture(fixture_path::AbstractString,
        target,
        near_oracle_raw::AbstractVector)
    root = dirname(dirname(@__DIR__))
    resolved_fixture_path = isabspath(fixture_path) ? fixture_path : joinpath(root, fixture_path)
    fixture = JSON3.read(read(resolved_fixture_path, String))
    @test String(fixture[:schema]) ==
        "bayesianmgmfrm.gmfrm_candidate_chain_study.v1"
    @test String(fixture[:family]) == "gmfrm"
    @test String(fixture[:scope]) == "scalar_gmfrm_fit_ready_candidate"
    @test String(fixture[:status]) == "internal_promotion_candidate"
    @test Bool(fixture[:public_fit]) == false
    @test Bool(fixture[:fit_ready]) == false
    @test String(fixture[:target]) == "_gmfrm_promotion_candidate_logdensity"
    @test String(fixture[:density_space]) == "raw_unconstrained"

    protocol = fixture[:protocol]
    thresholds = protocol[:thresholds]
    @test String(protocol[:protocol_id]) == "scalar_gmfrm_candidate_chain_v1"
    @test String(protocol[:backend]) == "advancedhmc"
    @test String(protocol[:sampler]) == "nuts"
    @test Int(protocol[:chains]) == 2
    @test Int(protocol[:warmup]) == 32
    @test Int(protocol[:draws]) == 32
    @test Float64(protocol[:step_size]) == 0.02
    @test Float64(protocol[:target_accept]) == 0.8
    @test Int(protocol[:max_depth]) == 5
    @test String(protocol[:metric]) == "unit"
    @test Bool(protocol[:split_chains])
    @test Float64(thresholds[:max_rhat]) == 1.2
    @test Float64(thresholds[:min_ess]) == 8.0
    @test Float64(thresholds[:min_ebfmi]) == 0.3
    @test Int(thresholds[:n_divergences]) == 0
    @test Int(thresholds[:n_max_treedepth]) == 0
    @test Int(thresholds[:n_failed_direct_constraints]) == 0
    @test Int(thresholds[:n_nonfinite_logdensity]) == 0
    @test Int(thresholds[:n_nonfinite_direct_loglikelihood]) == 0

    raw_names = Vector{String}(fixture[:raw_parameter_order])
    direct_names = Vector{String}(fixture[:direct_parameter_order])
    @test raw_names == target.blueprint.parameter_names
    @test direct_names == target.blueprint.constrained_parameter_names
    @test String(fixture[:raw_parameter_order_sha256]) == test_parameter_order_hash(raw_names)
    @test String(fixture[:direct_parameter_order_sha256]) ==
        test_parameter_order_hash(direct_names)

    study_fixtures = fixture[:fixtures]
    @test length(study_fixtures) == 2
    labels = Set(String(row[:fixture]) for row in study_fixtures)
    @test labels == Set(["near_oracle", "zero_centered"])
    for row in study_fixtures
        label = String(row[:fixture])
        initial_raw = Vector{Float64}(row[:initial_raw_parameter_values])
        if label == "near_oracle"
            @test initial_raw ≈ Float64.(collect(near_oracle_raw))
        elseif label == "zero_centered"
            @test initial_raw == zeros(length(near_oracle_raw))
        end
        @test length(Vector{Float64}(row[:initial_direct_parameter_values])) ==
            length(direct_names)

        summary = row[:summary]
        @test Bool(summary[:internal_passed])
        @test Bool(summary[:passed_protocol])
        @test String(summary[:internal_flag]) == "ok"
        @test Int(summary[:n_chains]) == Int(protocol[:chains])
        @test Int(summary[:draws_per_chain]) == Int(protocol[:draws])
        @test Int(summary[:total_draws]) ==
            Int(protocol[:chains]) * Int(protocol[:draws])
        @test Float64(summary[:max_rhat]) <= Float64(thresholds[:max_rhat])
        @test Float64(summary[:min_ess]) >= Float64(thresholds[:min_ess])
        @test Float64(summary[:e_bfmi]) >= Float64(thresholds[:min_ebfmi])
        @test Int(summary[:n_bad_rhat]) == 0
        @test Int(summary[:n_low_ess]) == 0
        @test Int(summary[:n_divergences]) == Int(thresholds[:n_divergences])
        @test Int(summary[:n_max_treedepth]) == Int(thresholds[:n_max_treedepth])
        @test Int(summary[:n_nonfinite_logdensity]) ==
            Int(thresholds[:n_nonfinite_logdensity])
        @test Int(summary[:n_nonfinite_direct_loglikelihood]) ==
            Int(thresholds[:n_nonfinite_direct_loglikelihood])
        @test Int(summary[:n_failed_direct_constraints]) ==
            Int(thresholds[:n_failed_direct_constraints])

        @test length(row[:sampler_rows]) == Int(protocol[:chains])
        @test all(sampler_row -> String(sampler_row[:flag]) == "ok", row[:sampler_rows])
        @test all(sampler_row -> Int(sampler_row[:n_divergences]) == 0,
            row[:sampler_rows])
        @test all(sampler_row -> Int(sampler_row[:n_max_treedepth]) == 0,
            row[:sampler_rows])
        @test all(sampler_row -> Float64(sampler_row[:e_bfmi]) >=
            Float64(thresholds[:min_ebfmi]), row[:sampler_rows])

        @test all(block_row -> String(block_row[:flag]) == "ok", row[:raw_block_rows])
        @test all(block_row -> String(block_row[:flag]) == "ok", row[:direct_block_rows])
        @test all(constraint_row -> Bool(constraint_row[:passed]),
            row[:direct_constraint_rows])
        @test all(constraint_row -> Int(constraint_row[:n_failed]) == 0,
            row[:direct_constraint_rows])

        pointwise = row[:pointwise]
        @test Int(pointwise[:n_observations]) == target.design.spec.data.n
        @test Int(pointwise[:n_draws]) == Int(summary[:total_draws])
        @test Int(pointwise[:n_nonfinite_pointwise]) == 0
        @test Int(pointwise[:n_nonfinite_loglikelihood]) == 0
        @test isfinite(Float64(pointwise[:minimum_pointwise_loglikelihood]))
        @test isfinite(Float64(pointwise[:maximum_pointwise_loglikelihood]))
        @test isfinite(Float64(pointwise[:minimum_loglikelihood]))
        @test isfinite(Float64(pointwise[:maximum_loglikelihood]))
    end

    overall = fixture[:summary]
    @test Int(overall[:n_fixtures]) == 2
    @test Int(overall[:n_passed_protocol]) == 2
    @test Bool(overall[:overall_passed])
    @test Float64(overall[:max_rhat]) <= Float64(thresholds[:max_rhat])
    @test Float64(overall[:min_ess]) >= Float64(thresholds[:min_ess])
    @test Float64(overall[:min_ebfmi]) >= Float64(thresholds[:min_ebfmi])
    @test Int(overall[:n_divergences]) == 0
    @test Int(overall[:n_max_treedepth]) == 0
    @test Int(overall[:n_failed_direct_constraints]) == 0
    @test Int(overall[:n_nonfinite_logdensity]) == 0
    @test Int(overall[:n_nonfinite_direct_loglikelihood]) == 0
end

function check_gmfrm_stress_chain_grid_fixture(fixture_path::AbstractString,
        target,
        near_oracle_raw::AbstractVector)
    root = dirname(dirname(@__DIR__))
    resolved_fixture_path = isabspath(fixture_path) ? fixture_path : joinpath(root, fixture_path)
    fixture = JSON3.read(read(resolved_fixture_path, String))
    @test String(fixture[:schema]) == "bayesianmgmfrm.gmfrm_stress_chain_grid.v1"
    @test String(fixture[:family]) == "gmfrm"
    @test String(fixture[:scope]) == "scalar_gmfrm_fit_ready_candidate"
    @test String(fixture[:status]) == "internal_promotion_candidate"
    @test Bool(fixture[:public_fit]) == false
    @test Bool(fixture[:fit_ready]) == false
    @test String(fixture[:target]) == "_gmfrm_promotion_candidate_logdensity"
    @test String(fixture[:density_space]) == "raw_unconstrained"

    protocol = fixture[:protocol]
    thresholds = protocol[:thresholds]
    @test String(protocol[:protocol_id]) == "scalar_gmfrm_stress_chain_grid_v1"
    @test Int(protocol[:chains]) == 2
    @test Int(protocol[:warmup]) == 96
    @test Int(protocol[:draws]) == 96
    @test String(protocol[:metric]) == "unit"
    @test Bool(protocol[:split_chains])
    @test Float64(thresholds[:max_rhat]) == 1.2
    @test Float64(thresholds[:min_ess]) == 16.0
    @test Float64(thresholds[:min_ebfmi]) == 0.3

    raw_names = Vector{String}(fixture[:raw_parameter_order])
    direct_names = Vector{String}(fixture[:direct_parameter_order])
    @test raw_names == target.blueprint.parameter_names
    @test direct_names == target.blueprint.constrained_parameter_names
    @test String(fixture[:raw_parameter_order_sha256]) == test_parameter_order_hash(raw_names)
    @test String(fixture[:direct_parameter_order_sha256]) ==
        test_parameter_order_hash(direct_names)

    scenarios = fixture[:scenarios]
    @test length(scenarios) == 3
    labels = Set(String(row[:scenario]) for row in scenarios)
    @test labels == Set([
        "near_oracle_long",
        "zero_centered_long",
        "near_oracle_high_acceptance",
    ])
    for row in scenarios
        label = String(row[:scenario])
        initial_raw = Vector{Float64}(row[:initial_raw_parameter_values])
        if label == "zero_centered_long"
            @test initial_raw == zeros(length(near_oracle_raw))
        else
            @test initial_raw ≈ Float64.(collect(near_oracle_raw))
        end
        @test length(Vector{Float64}(row[:initial_direct_parameter_values])) ==
            length(direct_names)

        controls = row[:controls]
        @test Float64(controls[:step_size]) > 0
        @test Float64(controls[:target_accept]) >= 0.8
        @test Int(controls[:max_depth]) >= 6
        @test Float64(controls[:init_jitter]) >= 0

        summary = row[:summary]
        @test Bool(summary[:internal_passed])
        @test Bool(summary[:passed_protocol])
        @test String(summary[:internal_flag]) == "ok"
        @test Int(summary[:n_chains]) == Int(protocol[:chains])
        @test Int(summary[:draws_per_chain]) == Int(protocol[:draws])
        @test Int(summary[:total_draws]) ==
            Int(protocol[:chains]) * Int(protocol[:draws])
        @test Float64(summary[:max_rhat]) <= Float64(thresholds[:max_rhat])
        @test Float64(summary[:min_ess]) >= Float64(thresholds[:min_ess])
        @test Float64(summary[:e_bfmi]) >= Float64(thresholds[:min_ebfmi])
        @test Int(summary[:n_bad_rhat]) == 0
        @test Int(summary[:n_low_ess]) == 0
        @test Int(summary[:n_divergences]) == Int(thresholds[:n_divergences])
        @test Int(summary[:n_max_treedepth]) == Int(thresholds[:n_max_treedepth])
        @test Int(summary[:n_nonfinite_logdensity]) ==
            Int(thresholds[:n_nonfinite_logdensity])
        @test Int(summary[:n_nonfinite_direct_loglikelihood]) ==
            Int(thresholds[:n_nonfinite_direct_loglikelihood])
        @test Int(summary[:n_failed_direct_constraints]) ==
            Int(thresholds[:n_failed_direct_constraints])
        @test all(sampler_row -> String(sampler_row[:flag]) == "ok", row[:sampler_rows])
        @test all(block_row -> String(block_row[:flag]) == "ok", row[:raw_block_rows])
        @test all(block_row -> String(block_row[:flag]) == "ok", row[:direct_block_rows])
        @test all(constraint_row -> Bool(constraint_row[:passed]),
            row[:direct_constraint_rows])

        pointwise = row[:pointwise]
        @test Int(pointwise[:n_observations]) == target.design.spec.data.n
        @test Int(pointwise[:n_draws]) == Int(summary[:total_draws])
        @test Int(pointwise[:n_nonfinite_pointwise]) == 0
        @test Int(pointwise[:n_nonfinite_loglikelihood]) == 0
    end

    overall = fixture[:summary]
    @test Int(overall[:n_scenarios]) == 3
    @test Int(overall[:n_passed_protocol]) == 3
    @test Bool(overall[:overall_passed])
    @test Float64(overall[:max_rhat]) <= Float64(thresholds[:max_rhat])
    @test Float64(overall[:min_ess]) >= Float64(thresholds[:min_ess])
    @test Float64(overall[:min_ebfmi]) >= Float64(thresholds[:min_ebfmi])
    @test Int(overall[:n_divergences]) == 0
    @test Int(overall[:n_max_treedepth]) == 0
    @test Int(overall[:n_failed_direct_constraints]) == 0
    @test Int(overall[:n_nonfinite_logdensity]) == 0
    @test Int(overall[:n_nonfinite_direct_loglikelihood]) == 0
end

function check_mgmfrm_candidate_chain_study_fixture(fixture_path::AbstractString,
        target,
        near_oracle_raw::AbstractVector)
    root = dirname(dirname(@__DIR__))
    resolved_fixture_path = isabspath(fixture_path) ? fixture_path : joinpath(root, fixture_path)
    fixture = JSON3.read(read(resolved_fixture_path, String))
    @test String(fixture[:schema]) ==
        "bayesianmgmfrm.mgmfrm_candidate_chain_study.v1"
    @test String(fixture[:family]) == "mgmfrm"
    @test String(fixture[:scope]) == "minimal_confirmatory_mgmfrm_candidate"
    @test String(fixture[:status]) == "internal_fit_ready_candidate"
    @test Bool(fixture[:public_fit]) == false
    @test Bool(fixture[:fit_ready]) == false
    @test String(fixture[:target]) == "_source_fixture_logdensity"
    @test String(fixture[:density_space]) == "raw_unconstrained"
    @test Int(fixture[:dimensions]) == target.design.spec.dimensions
    @test json_bool_matrix(fixture[:q_matrix]) == target.design.spec.q_matrix
    @test String(fixture[:latent_correlation]) == "identity_fixed"
    @test String(fixture[:ability_scale]) == "unit_variance_by_dimension"
    @test Float64(fixture[:source_scale]) == 1.7

    protocol = fixture[:protocol]
    thresholds = protocol[:thresholds]
    @test String(protocol[:protocol_id]) == "confirmatory_mgmfrm_candidate_chain_v1"
    @test String(protocol[:backend]) == "advancedhmc"
    @test String(protocol[:sampler]) == "nuts"
    @test Int(protocol[:chains]) == 2
    @test Int(protocol[:warmup]) == 32
    @test Int(protocol[:draws]) == 32
    @test Float64(protocol[:step_size]) == 0.02
    @test Float64(protocol[:target_accept]) == 0.8
    @test Int(protocol[:max_depth]) == 8
    @test String(protocol[:metric]) == "unit"
    @test Bool(protocol[:split_chains])
    @test Float64(thresholds[:max_rhat]) == 1.35
    @test Float64(thresholds[:min_ess]) == 6.0
    @test Float64(thresholds[:min_ebfmi]) == 0.3
    @test Int(thresholds[:n_divergences]) == 0
    @test Int(thresholds[:n_max_treedepth]) == 0
    @test Int(thresholds[:n_failed_direct_constraints]) == 0
    @test Int(thresholds[:n_nonfinite_logdensity]) == 0
    @test Int(thresholds[:n_nonfinite_direct_loglikelihood]) == 0

    raw_names = Vector{String}(fixture[:raw_parameter_order])
    direct_names = Vector{String}(fixture[:direct_parameter_order])
    @test raw_names == target.blueprint.parameter_names
    @test direct_names == target.blueprint.constrained_parameter_names
    @test String(fixture[:raw_parameter_order_sha256]) == test_parameter_order_hash(raw_names)
    @test String(fixture[:direct_parameter_order_sha256]) ==
        test_parameter_order_hash(direct_names)

    study_fixtures = fixture[:fixtures]
    @test length(study_fixtures) == 2
    labels = Set(String(row[:fixture]) for row in study_fixtures)
    @test labels == Set(["near_oracle", "zero_centered"])
    for row in study_fixtures
        label = String(row[:fixture])
        initial_raw = Vector{Float64}(row[:initial_raw_parameter_values])
        if label == "near_oracle"
            @test initial_raw ≈ Float64.(collect(near_oracle_raw))
        elseif label == "zero_centered"
            @test initial_raw == zeros(length(near_oracle_raw))
        end
        @test length(Vector{Float64}(row[:initial_direct_parameter_values])) ==
            length(direct_names)

        summary = row[:summary]
        @test Bool(summary[:internal_passed])
        @test Bool(summary[:passed_protocol])
        @test String(summary[:internal_flag]) == "ok"
        @test Int(summary[:n_chains]) == Int(protocol[:chains])
        @test Int(summary[:draws_per_chain]) == Int(protocol[:draws])
        @test Int(summary[:total_draws]) ==
            Int(protocol[:chains]) * Int(protocol[:draws])
        @test Float64(summary[:max_rhat]) <= Float64(thresholds[:max_rhat])
        @test Float64(summary[:min_ess]) >= Float64(thresholds[:min_ess])
        @test Float64(summary[:e_bfmi]) >= Float64(thresholds[:min_ebfmi])
        @test Int(summary[:n_bad_rhat]) == 0
        @test Int(summary[:n_low_ess]) == 0
        @test Int(summary[:n_divergences]) == Int(thresholds[:n_divergences])
        @test Int(summary[:n_max_treedepth]) == Int(thresholds[:n_max_treedepth])
        @test Int(summary[:n_nonfinite_logdensity]) ==
            Int(thresholds[:n_nonfinite_logdensity])
        @test Int(summary[:n_nonfinite_direct_loglikelihood]) ==
            Int(thresholds[:n_nonfinite_direct_loglikelihood])
        @test Int(summary[:n_failed_direct_constraints]) ==
            Int(thresholds[:n_failed_direct_constraints])

        @test length(row[:sampler_rows]) == Int(protocol[:chains])
        @test all(sampler_row -> String(sampler_row[:flag]) == "ok", row[:sampler_rows])
        @test all(sampler_row -> Int(sampler_row[:n_divergences]) == 0,
            row[:sampler_rows])
        @test all(sampler_row -> Int(sampler_row[:n_max_treedepth]) == 0,
            row[:sampler_rows])
        @test all(sampler_row -> Float64(sampler_row[:e_bfmi]) >=
            Float64(thresholds[:min_ebfmi]), row[:sampler_rows])

        @test all(block_row -> String(block_row[:flag]) == "ok", row[:raw_block_rows])
        @test all(block_row -> String(block_row[:flag]) == "ok", row[:direct_block_rows])
        @test all(constraint_row -> Bool(constraint_row[:passed]),
            row[:direct_constraint_rows])
        @test all(constraint_row -> Int(constraint_row[:n_failed]) == 0,
            row[:direct_constraint_rows])

        pointwise = row[:pointwise]
        @test Int(pointwise[:n_observations]) == target.design.spec.data.n
        @test Int(pointwise[:n_draws]) == Int(summary[:total_draws])
        @test Int(pointwise[:n_nonfinite_pointwise]) == 0
        @test Int(pointwise[:n_nonfinite_loglikelihood]) == 0
        @test isfinite(Float64(pointwise[:minimum_pointwise_loglikelihood]))
        @test isfinite(Float64(pointwise[:maximum_pointwise_loglikelihood]))
        @test isfinite(Float64(pointwise[:minimum_loglikelihood]))
        @test isfinite(Float64(pointwise[:maximum_loglikelihood]))
    end

    overall = fixture[:summary]
    @test Int(overall[:n_fixtures]) == 2
    @test Int(overall[:n_passed_protocol]) == 2
    @test Bool(overall[:overall_passed])
    @test Float64(overall[:max_rhat]) <= Float64(thresholds[:max_rhat])
    @test Float64(overall[:min_ess]) >= Float64(thresholds[:min_ess])
    @test Float64(overall[:min_ebfmi]) >= Float64(thresholds[:min_ebfmi])
    @test Int(overall[:n_divergences]) == 0
    @test Int(overall[:n_max_treedepth]) == 0
    @test Int(overall[:n_failed_direct_constraints]) == 0
    @test Int(overall[:n_nonfinite_logdensity]) == 0
    @test Int(overall[:n_nonfinite_direct_loglikelihood]) == 0
end
