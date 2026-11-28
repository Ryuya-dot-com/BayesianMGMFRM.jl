function check_mgmfrm_literature_anchored_synthetic_benchmark_fixture(
        fixture_path::AbstractString)
    root = dirname(dirname(@__DIR__))
    resolved_fixture_path =
        isabspath(fixture_path) ? fixture_path : joinpath(root, fixture_path)
    fixture = JSON3.read(read(resolved_fixture_path, String))
    @test String(fixture[:schema]) ==
        "bayesianmgmfrm.mgmfrm_literature_anchored_synthetic_benchmark.v1"
    @test String(fixture[:family]) == "gmfrm_mgmfrm"
    @test String(fixture[:scope]) ==
        "literature_anchored_synthetic_benchmark"
    @test String(fixture[:status]) == "pilot_datasets_materialized"
    @test String(fixture[:decision]) ==
        "use_for_known_truth_and_external_software_bridge_preparation_only"
    @test Bool(fixture[:synthetic_data_only])
    @test Bool(fixture[:construct_validity_evidence]) == false
    @test Bool(fixture[:external_software_validation_completed]) == false
    @test Bool(fixture[:independent_review_completed]) == false
    @test Bool(fixture[:publication_or_registration_action]) == false

    protocol = fixture[:protocol]
    @test String(protocol[:protocol_id]) ==
        "mgmfrm_literature_anchored_synthetic_benchmark_v1"
    @test String(protocol[:source_discovery]) == "zotero_library_review"
    @test String(protocol[:committed_reference_policy]) ==
        "public_doi_and_url_only_no_reference_manager_item_keys"
    @test String(protocol[:generator]) == "standalone_equation_implementation"
    @test Bool(protocol[:package_simulate_responses_called]) == false
    @test Bool(protocol[:package_source_oracle_checked_before_write])
    @test String(protocol[:generator_source]) ==
        "scripts/generate_mgmfrm_literature_anchored_synthetic_benchmark.jl"
    @test String(protocol[:generator_source_sha256]) == file_sha256(joinpath(
        root,
        String(protocol[:generator_source]),
    ))
    seed_policy = protocol[:seed_policy]
    @test Int(seed_policy[:base_seed]) == 20260707
    @test Int(seed_policy[:stream_offsets][:truth]) == 1
    @test Int(seed_policy[:stream_offsets][:response]) == 3

    references = fixture[:reference_records]
    @test length(references) == 4
    @test all(row -> String(row[:source]) == "doi", references)
    @test all(row -> !haskey(row, :item_key) && !haskey(row, :zotero_key),
        references)
    @test Set(String(row[:doi]) for row in references) == Set([
        "10.1007/s41237-020-00115-7",
        "10.1007/s41237-021-00144-w",
        "10.1177/0013164418814898",
        "10.1177/0146621604271053",
    ])

    specifications = fixture[:benchmark_specifications]
    @test length(specifications) == 4
    @test Set(String(row[:benchmark_id]) for row in specifications) == Set([
        "uto_ueno_2020_scalar_recovery_smallest_cell",
        "uto_2021_fixed_q_recovery_smallest_cell",
        "da_silva_2019_q_mask_stress_grid",
        "wang_wilson_2005_conquest_mrcml_bridge",
    ])
    uto2020_spec = only(filter(row -> String(row[:benchmark_id]) ==
        "uto_ueno_2020_scalar_recovery_smallest_cell", specifications))
    @test Int(uto2020_spec[:selected_pilot_cell][:persons]) == 30
    @test Int(uto2020_spec[:selected_pilot_cell][:items]) == 3
    @test Int(uto2020_spec[:selected_pilot_cell][:raters]) == 5
    @test String(uto2020_spec[:alignment][:sample_size_cell]) == "paper_exact"
    uto2021_spec = only(filter(row -> String(row[:benchmark_id]) ==
        "uto_2021_fixed_q_recovery_smallest_cell", specifications))
    @test Int(uto2021_spec[:selected_pilot_cell][:dimensions]) == 2
    @test String(uto2021_spec[:alignment][:ability_combination]) ==
        "loading_weighted_sum"
    @test String(uto2021_spec[:alignment][:loading_structure]) ==
        "package_adapted_fixed_q"
    @test Float64(uto2021_spec[:alignment][:paper_nonprimary_anchor_loading]) ==
        0.2
    @test all(row -> String(row[:materialization]) == "design_only",
        filter(row -> String(row[:benchmark_id]) in (
            "da_silva_2019_q_mask_stress_grid",
            "wang_wilson_2005_conquest_mrcml_bridge",
        ), specifications))

    function observation_sha256(observations)
        io = IOBuffer()
        println(io, "person,rater,item,score")
        for row in eachindex(observations[:person])
            println(io,
                Int(observations[:person][row]), ',',
                Int(observations[:rater][row]), ',',
                Int(observations[:item][row]), ',',
                Int(observations[:score][row]),
            )
        end
        return bytes2hex(sha256(take!(io)))
    end

    function expected_probability(dataset, check)
        truth = dataset[:truth]
        person = Int(check[:person])
        rater = Int(check[:rater])
        item = Int(check[:item])
        categories = length(dataset[:design][:category_levels])
        eta = zeros(Float64, categories)
        if String(dataset[:family]) == "gmfrm"
            location = Float64(truth[:person_ability][person]) -
                Float64(truth[:item_difficulty][item]) -
                Float64(truth[:rater_severity][rater])
            scale = Float64(truth[:item_discrimination][item]) *
                Float64(truth[:rater_consistency][rater])
            for category in 2:categories
                eta[category] = eta[category - 1] + scale *
                    (location - Float64(truth[:rater_steps][rater][category]))
            end
        else
            ability_score = sum(
                Float64(truth[:item_dimension_discrimination][item][dimension]) *
                Float64(truth[:person_ability][person][dimension])
                for dimension in 1:Int(dataset[:design][:n_dimensions])
            )
            location = ability_score - Float64(truth[:item_difficulty][item]) -
                Float64(truth[:rater_severity][rater])
            scale = 1.7 * Float64(truth[:rater_consistency][rater])
            for category in 2:categories
                eta[category] = eta[category - 1] + scale *
                    (location - Float64(truth[:item_steps][item][category]))
            end
        end
        weights = exp.(eta .- maximum(eta))
        return weights ./ sum(weights)
    end

    datasets = fixture[:datasets]
    @test length(datasets) == 2
    @test Set(String(row[:dataset_id]) for row in datasets) == Set([
        "uto_ueno_2020_scalar_recovery_smallest_cell_rep01",
        "uto_2021_fixed_q_recovery_smallest_cell_rep01",
    ])
    uto2021_dataset = only(filter(row -> String(row[:dataset_id]) ==
        "uto_2021_fixed_q_recovery_smallest_cell_rep01", datasets))
    @test String(uto2021_dataset[:equation][:ability_combination]) ==
        "loading_weighted_sum"
    @test String(uto2021_dataset[:adaptation][:ability_combination_scope]) ==
        "record_generation_formula_not_compensatory_classification_claim"
    seed_values = Int[]
    for dataset in datasets
        push!(seed_values, Int(dataset[:seeds][:truth]))
        push!(seed_values, Int(dataset[:seeds][:response]))
    end
    @test length(unique(seed_values)) == 4
    for dataset in datasets
        design = dataset[:design]
        observations = dataset[:observations]
        n_observations = Int(design[:n_observations])
        @test all(key -> length(observations[key]) == n_observations,
            (:person, :rater, :item, :score))
        @test Set(Int.(observations[:score])) ==
            Set(Int.(design[:category_levels]))
        @test String(dataset[:checksums][:observations_sha256]) ==
            observation_sha256(observations)
        @test occursin(r"^[0-9a-f]{64}$",
            String(dataset[:checksums][:truth_sha256]))
        @test Bool(dataset[:contains_personal_data]) == false
        @test String(dataset[:materialization]) == "row_level_synthetic_pilot"
        @test String(dataset[:equation][:implementation]) ==
            "standalone_adjacent_category_softmax"
        @test Bool(dataset[:equation][:package_generator_called]) == false
        checks = dataset[:generator_checks]
        tolerance = Float64(checks[:tolerance])
        @test Float64(checks[:max_abs_probability_error]) <= tolerance
        @test length(checks[:selected_rows]) == 3
        for check in checks[:selected_rows]
            row = Int(check[:row])
            @test Int(observations[:person][row]) == Int(check[:person])
            @test Int(observations[:rater][row]) == Int(check[:rater])
            @test Int(observations[:item][row]) == Int(check[:item])
            independent = Float64.(check[:independent_generator_probabilities])
            oracle = Float64.(check[:package_source_oracle_probabilities])
            @test sum(independent) ≈ 1.0 atol = 1e-12
            @test sum(oracle) ≈ 1.0 atol = 1e-12
            @test independent ≈ oracle atol = tolerance rtol = 0.0
            @test independent ≈ expected_probability(dataset, check) atol = 1e-12
        end
        @test Bool(dataset[:summary][:all_categories_observed])
        @test Bool(dataset[:summary][:complete_person_coverage])
        @test Bool(dataset[:summary][:complete_rater_coverage])
        @test Bool(dataset[:summary][:complete_item_coverage])
    end

    gmfrm = only(filter(row -> String(row[:family]) == "gmfrm", datasets))
    @test Int(gmfrm[:design][:n_observations]) == 450
    @test isapprox(sum(Float64.(gmfrm[:truth][:item_difficulty])), 0.0;
        atol = 1e-12)
    @test isapprox(prod(Float64.(gmfrm[:truth][:item_discrimination])), 1.0;
        atol = 1e-12)
    @test all(steps -> Float64(first(steps)) == 0.0 &&
        isapprox(sum(Float64.(steps)), 0.0; atol = 1e-12),
        gmfrm[:truth][:rater_steps])

    mgmfrm = only(filter(row -> String(row[:family]) == "mgmfrm", datasets))
    @test Int(mgmfrm[:design][:n_observations]) == 1250
    @test [[Bool(value) for value in row] for row in mgmfrm[:design][:q_matrix]] == [
        [true, false],
        [false, true],
        [true, false],
        [false, true],
        [true, true],
    ]
    @test Float64(mgmfrm[:truth][:item_dimension_discrimination][1][1]) == 1.5
    @test Float64(mgmfrm[:truth][:item_dimension_discrimination][2][2]) == 1.5
    @test isapprox(sum(Float64.(mgmfrm[:truth][:rater_severity])), 0.0;
        atol = 1e-12)
    @test isapprox(prod(Float64.(mgmfrm[:truth][:rater_consistency])), 1.0;
        atol = 1e-12)
    @test all(steps -> Float64(first(steps)) == 0.0 &&
        isapprox(sum(Float64.(steps)), 0.0; atol = 1e-12),
        mgmfrm[:truth][:item_steps])
    @test String(mgmfrm[:adaptation][:type]) == "confirmatory_fixed_q"
    @test Bool(mgmfrm[:adaptation][:paper_exact_loading_recovery_claim]) == false
    @test occursin(r"^[0-9a-f]{64}$",
        String(mgmfrm[:checksums][:q_matrix_sha256]))

    bridges = fixture[:external_validation_bridges]
    @test Set(String(row[:software]) for row in bridges) ==
        Set(["tam", "facets", "conquest"])
    tam_bridge = only(row for row in bridges if String(row[:software]) == "tam")
    @test String(tam_bridge[:status]) ==
        "direct_agreement_policy_frozen_and_multiaxially_refined_multirep_package_fits_pending"
    @test String(tam_bridge[:overlap_target]) ==
        "many_facet_rasch_partial_credit_baseline"
    @test String(tam_bridge[:prepared_dataset]) ==
        "test/fixtures/mgmfrm_tam_overlap_baseline.json"
    @test String(tam_bridge[:prepared_csv]) ==
        "test/fixtures/mgmfrm_tam_overlap_baseline.csv"
    @test String(tam_bridge[:execution_review]) ==
        "test/fixtures/mgmfrm_tam_overlap_execution_review.json"
    @test String(tam_bridge[:comparison_policy_review]) ==
        "test/fixtures/mgmfrm_tam_comparison_policy_review.json"
    @test String(tam_bridge[:multireplication_comparison]) ==
        "test/fixtures/mgmfrm_tam_multireplication_comparison.json"
    @test String(tam_bridge[:direct_estimate_pilot]) ==
        "test/fixtures/mgmfrm_tam_direct_estimate_pilot.json"
    @test String(tam_bridge[:direct_agreement_policy]) ==
        "test/fixtures/mgmfrm_tam_direct_agreement_policy.json"
    @test String(tam_bridge[:direct_agreement_policy_refinement]) ==
        "test/fixtures/mgmfrm_tam_direct_agreement_policy_refinement.json"
    @test all(row -> String(row[:status]) == "not_executed",
        filter(row -> String(row[:software]) in ("facets", "conquest"),
            bridges))
    independent_review = fixture[:independent_review]
    @test Bool(independent_review[:separate_from_external_software_comparison])
    @test String(independent_review[:status]) ==
        "packet_frozen_review_not_started"
    @test String(independent_review[:review_packet_artifact]) ==
        "test/fixtures/mgmfrm_literature_anchored_independent_review_packet.json"
    @test String(independent_review[:review_packet_schema]) ==
        "bayesianmgmfrm.mgmfrm_literature_anchored_independent_review_packet.v1"
    @test Set(String.(independent_review[:remaining_requirements])) == Set([
        "assign_independent_reviewer",
        "attach_signed_independent_review_manifest",
        "record_per_claim_review_decisions",
    ])
    claims = fixture[:claim_ledger]
    @test any(row -> String(row[:claim]) == "parameter_recovery" &&
        Bool(row[:supported]) == false, claims)
    @test any(row -> String(row[:claim]) == "external_software_agreement" &&
        Bool(row[:supported]) == false, claims)
    @test any(row -> String(row[:claim]) == "external_construct_validity" &&
        Bool(row[:supported]) == false, claims)
    @test any(row -> String(row[:claim]) == "independent_review" &&
        Bool(row[:supported]) == false, claims)

    summary = fixture[:summary]
    @test Bool(summary[:passed])
    @test Int(summary[:n_reference_records]) == 4
    @test Int(summary[:n_benchmark_specifications]) == 4
    @test Int(summary[:n_materialized_datasets]) == 2
    @test Int(summary[:n_materialized_observations]) == 1700
    @test Bool(summary[:standalone_generator_oracle_agreement])
    @test Bool(summary[:row_and_category_coverage_passed])
    @test Bool(summary[:parameter_recovery_completed]) == false
    @test Bool(summary[:external_software_validation_completed]) == false
    @test Bool(summary[:external_construct_validation_completed]) == false
    @test Bool(summary[:independent_review_completed]) == false
    @test Bool(summary[:public_claim_release_allowed]) == false
    @test Set(String.(summary[:next_gates])) == Set([
        "run_predeclared_recovery_refits_across_paper_grid_cells",
        "run_predeclared_multireplication_package_vs_tam_direct_agreement_under_refined_adjudication",
        "add_facets_unit_discrimination_overlap_dataset_and_adapter",
        "add_conquest_mrcml_overlap_dataset_and_adapter",
        "assign_independent_reviewer_and_attach_signed_review",
        "attach_real_external_construct_dataset_separately",
    ])
end

function check_mgmfrm_tam_overlap_baseline_fixture(fixture_path::AbstractString)
    root = dirname(dirname(@__DIR__))
    resolved_fixture_path =
        isabspath(fixture_path) ? fixture_path : joinpath(root, fixture_path)
    fixture = JSON3.read(read(resolved_fixture_path, String))
    @test String(fixture[:schema]) ==
        "bayesianmgmfrm.mgmfrm_tam_overlap_baseline.v1"
    @test String(fixture[:family]) == "mfrm"
    @test String(fixture[:scope]) == "tam_overlap_baseline"
    @test String(fixture[:status]) == "tam_overlap_dataset_prepared"
    @test String(fixture[:decision]) ==
        "prepare_tam_overlap_baseline_do_not_claim_validation"
    @test Bool(fixture[:local_only])
    @test Bool(fixture[:synthetic_data_only])
    @test String(fixture[:external_software]) == "tam"
    @test Bool(fixture[:external_software_validation_completed]) == false
    @test Bool(fixture[:tam_execution_completed]) == false
    @test Bool(fixture[:parameter_comparison_completed]) == false
    @test Bool(fixture[:public_claim_release_allowed]) == false
    @test Bool(fixture[:publication_or_registration_action]) == false

    protocol = fixture[:protocol]
    @test String(protocol[:protocol_id]) == "mgmfrm_tam_overlap_baseline_v1"
    @test String(protocol[:generator]) == "standalone_mfrm_overlap_generator"
    @test String(protocol[:generator_independence_scope]) ==
        "response_sampling_does_not_call_package_probability_or_simulation_helpers"
    @test Bool(protocol[:package_oracle_checked_before_write])
    @test String(protocol[:generator_source]) ==
        "scripts/generate_mgmfrm_tam_overlap_baseline.jl"
    @test String(protocol[:generator_source_sha256]) == file_sha256(joinpath(
        root,
        String(protocol[:generator_source]),
    ))
    @test Int(protocol[:base_seed]) == 20260711
    @test Int(protocol[:truth_seed]) != Int(protocol[:response_seed])

    references = fixture[:reference_records]
    @test length(references) == 3
    @test Set(String(row[:source]) for row in references) ==
        Set(["cran", "pkgdown", "rdrr"])

    target = fixture[:overlap_target]
    @test String(target[:software]) == "tam"
    @test String(target[:r_package]) == "TAM"
    @test String(target[:target_function]) == "TAM::tam.mml.mfr"
    @test String(target[:target_model]) ==
        "many_facet_rasch_partial_credit"
    @test String(target[:tam_formulaA]) == "~ item + rater + item:step"
    @test String(target[:tam_constraint]) == "cases"
    @test String(target[:package_family]) == "mfrm"
    @test String(target[:package_thresholds]) == "partial_credit"
    @test Set(String.(target[:excluded_from_overlap])) == Set([
        "item_discrimination",
        "rater_consistency",
        "multidimensional_loading",
        "free_latent_correlation",
        "construct_validity_claim",
    ])

    design = fixture[:design]
    @test Int(design[:n_persons]) == 40
    @test Int(design[:n_items]) == 5
    @test Int(design[:n_raters]) == 4
    @test Int(design[:n_dimensions]) == 1
    @test Int.(design[:category_levels]) == [0, 1, 2, 3]
    @test String(design[:assignment]) == "fully_crossed"
    @test Int(design[:n_observations]) == 800

    equation = fixture[:equation]
    @test String(equation[:implementation]) ==
        "standalone_adjacent_category_softmax"
    @test String(equation[:location]) ==
        "person_ability_minus_rater_severity_minus_item_difficulty"
    @test Float64(equation[:item_discrimination]) == 1.0
    @test Float64(equation[:rater_consistency]) == 1.0
    @test Bool(equation[:package_generator_called]) == false

    observations = fixture[:observations]
    @test all(key -> length(observations[key]) == Int(design[:n_observations]),
        (:person, :rater, :item, :score))
    @test Set(Int.(observations[:person])) == Set(1:40)
    @test Set(Int.(observations[:rater])) == Set(1:4)
    @test Set(Int.(observations[:item])) == Set(1:5)
    @test Set(Int.(observations[:score])) == Set(0:3)

    truth = fixture[:truth]
    @test length(truth[:person_ability]) == 40
    @test Float64(truth[:rater_severity][1]) == 0.0
    @test Float64(truth[:item_difficulty][1]) == 0.0
    @test length(truth[:item_steps]) == 5
    @test all(steps -> isapprox(sum(Float64.(steps)), 0.0; atol = 1e-12),
        truth[:item_steps])

    tam_export = fixture[:tam_export]
    @test String(tam_export[:path]) ==
        "test/fixtures/mgmfrm_tam_overlap_baseline.csv"
    csv_path = joinpath(root, String(tam_export[:path]))
    @test isfile(csv_path)
    @test String(tam_export[:sha256]) == file_sha256(csv_path)
    csv_lines = readlines(csv_path)
    @test length(csv_lines) == 801
    @test first(csv_lines) == "person,rater,item,score"
    @test all(line -> occursin(r"^[0-9]+,[0-9]+,[0-9]+,[0-3]$", line),
        csv_lines[2:end])
    @test String(tam_export[:response_column]) == "score"
    @test Set(String.(tam_export[:facet_columns])) == Set(["item", "rater"])
    @test String(tam_export[:runner_template_status]) == "not_executed"
    runner = String.(tam_export[:runner_template])
    @test any(contains("TAM::tam.mml.mfr"), runner)
    @test any(contains("formulaA <- ~ item + rater + item:step"), runner)
    @test any(contains("constraint = \"cases\""), runner)

    checksums = fixture[:checksums]
    @test String(checksums[:observations_sha256]) ==
        String(tam_export[:sha256])
    @test occursin(r"^[0-9a-f]{64}$", String(checksums[:truth_sha256]))

    generator_checks = fixture[:generator_checks]
    @test String(generator_checks[:package_oracle]) ==
        "predictive_probabilities_mfrm_partial_credit"
    @test Float64(generator_checks[:max_abs_probability_error]) <=
        Float64(generator_checks[:tolerance])
    @test length(generator_checks[:selected_rows]) == 3
    for row in generator_checks[:selected_rows]
        independent = Float64.(row[:independent_generator_probabilities])
        oracle = Float64.(row[:package_mfrm_oracle_probabilities])
        @test sum(independent) ≈ 1.0 atol = 1e-12
        @test sum(oracle) ≈ 1.0 atol = 1e-12
        @test independent ≈ oracle atol = Float64(generator_checks[:tolerance]) rtol = 0.0
    end

    @test Set(String.(fixture[:claim_limits])) == Set([
        "tam_export_prepared_not_executed",
        "no_tam_parameter_estimate_comparison",
        "no_facets_or_conquest_comparison",
        "no_generalized_gmfrm_or_mgmfrm_overlap_claim",
        "no_external_construct_validity_claim",
        "no_public_claim_release",
    ])

    summary = fixture[:summary]
    @test Bool(summary[:passed])
    @test Int(summary[:n_reference_records]) == 3
    @test Int(summary[:n_observations]) == 800
    @test Bool(summary[:all_categories_observed])
    @test Bool(summary[:tam_csv_written])
    @test String(summary[:tam_csv_sha256]) == file_sha256(csv_path)
    @test Bool(summary[:tam_execution_completed]) == false
    @test Bool(summary[:external_software_validation_completed]) == false
    @test Bool(summary[:public_claim_release_allowed]) == false
    @test String(summary[:next_gate]) ==
        "run_tam_mml_mfr_and_compare_parameter_table_under_recorded_adapter"
end

function check_mgmfrm_tam_overlap_execution_review_fixture(
        fixture_path::AbstractString)
    root = dirname(dirname(@__DIR__))
    resolved_fixture_path =
        isabspath(fixture_path) ? fixture_path : joinpath(root, fixture_path)
    fixture = JSON3.read(read(resolved_fixture_path, String))
    @test String(fixture[:schema]) ==
        "bayesianmgmfrm.mgmfrm_tam_overlap_execution_review.v1"
    @test String(fixture[:family]) == "mfrm"
    @test String(fixture[:scope]) == "tam_overlap_execution_review"
    @test String(fixture[:status]) == "tam_overlap_execution_recorded"
    @test String(fixture[:decision]) ==
        "record_tam_execution_keep_external_validation_claim_blocked"
    @test Bool(fixture[:local_only])
    @test String(fixture[:external_software]) == "tam"
    @test Bool(fixture[:tam_execution_completed])
    @test Bool(fixture[:tam_parameter_table_extracted])
    @test Bool(fixture[:parameter_comparison_completed])
    @test Bool(fixture[:external_software_validation_completed]) == false
    @test Bool(fixture[:public_claim_release_allowed]) == false
    @test Bool(fixture[:publication_or_registration_action]) == false

    protocol = fixture[:protocol]
    @test String(protocol[:protocol_id]) ==
        "mgmfrm_tam_overlap_execution_review_v1"
    @test String(protocol[:generator]) ==
        "scripts/generate_mgmfrm_tam_overlap_execution_review.jl"
    @test String(protocol[:generator_source_sha256]) == file_sha256(joinpath(
        root,
        String(protocol[:generator]),
    ))
    @test String(protocol[:baseline_artifact]) ==
        "test/fixtures/mgmfrm_tam_overlap_baseline.json"
    @test String(protocol[:baseline_artifact_sha256]) == file_sha256(joinpath(
        root,
        String(protocol[:baseline_artifact]),
    ))
    @test String(protocol[:baseline_csv]) ==
        "test/fixtures/mgmfrm_tam_overlap_baseline.csv"
    @test String(protocol[:baseline_csv_sha256]) == file_sha256(joinpath(
        root,
        String(protocol[:baseline_csv]),
    ))
    @test !isempty(String(protocol[:rscript_path]))
    @test String(protocol[:r_command]) == "TAM_tam_mml_mfr"
    @test String(protocol[:tam_formulaA]) == "~ item + rater + item:step"
    @test String(protocol[:tam_constraint]) == "cases"

    environment = fixture[:tam_environment]
    @test occursin("R version", String(environment[:r_version]))
    @test occursin(r"^[0-9]+\.[0-9]+\.[0-9]+$",
        String(environment[:tam_version]))
    @test !isempty(String(environment[:rscript_path]))

    fit = fixture[:tam_fit_summary]
    @test Int(fit[:iter]) > 0
    @test isfinite(Float64(fit[:deviance]))
    @test 0.0 < Float64(fit[:eap_rel]) <= 1.0
    @test Int(fit[:n_persons]) == 40
    @test isfinite(Float64(fit[:loglike]))
    @test isfinite(Float64(fit[:aic]))
    @test isfinite(Float64(fit[:bic]))
    @test Int(fit[:n_parameters]) == 19
    @test Bool(fit[:stdout_contains_pseudo_facet_notice])
    @test Bool(fit[:stderr_empty])

    parameters = fixture[:tam_parameter_rows]
    @test length(parameters) == 29
    @test count(row -> String(row[:facet]) == "item", parameters) == 5
    @test count(row -> String(row[:facet]) == "rater", parameters) == 4
    @test count(row -> String(row[:facet]) == "psf", parameters) == 5
    @test count(row -> String(row[:facet]) == "item:step", parameters) == 15
    @test all(row -> isfinite(Float64(row[:xsi])), parameters)
    @test all(row -> Float64(row[:se_xsi]) >= 0.0, parameters)

    comparisons = fixture[:parameter_comparison_rows]
    @test length(comparisons) == 3
    @test Set(String(row[:block]) for row in comparisons) == Set([
        "item_difficulty",
        "rater_severity",
        "item_step",
    ])
    expected_n = Dict(
        "item_difficulty" => 5,
        "rater_severity" => 4,
        "item_step" => 15,
    )
    expected_interpretation = Dict(
        "item_difficulty" => "diagnostic_overlap_not_claim_threshold",
        "rater_severity" => "diagnostic_overlap_not_claim_threshold",
        "item_step" => "structurally_audited_numerically_pilot_only",
    )
    for row in comparisons
        block = String(row[:block])
        @test Int(row[:n_parameters]) == expected_n[block]
        @test Float64(row[:pearson_correlation]) > 0.0
        @test isfinite(Float64(row[:mean_abs_difference]))
        @test isfinite(Float64(row[:max_abs_difference]))
        @test isfinite(Float64(row[:mean_signed_difference]))
        @test String(row[:interpretation]) == expected_interpretation[block]
    end

    @test Set(String.(fixture[:claim_limits])) == Set([
        "single_local_tam_overlap_execution_only",
        "parameter_differences_include_sampling_error",
        "item_step_adapter_structure_audited_single_pilot_only",
        "no_facets_or_conquest_execution",
        "no_generalized_gmfrm_or_mgmfrm_external_validation",
        "no_external_construct_validity_claim",
        "no_public_claim_release",
    ])

    hashes = fixture[:output_hashes]
    @test occursin(r"^[0-9a-f]{64}$",
        String(hashes[:transient_tam_xsi_facets_csv_sha256]))
    @test occursin(r"^[0-9a-f]{64}$",
        String(hashes[:transient_tam_summary_csv_sha256]))
    @test occursin(r"^[0-9a-f]{64}$",
        String(hashes[:transient_tam_formula_audit_csv_sha256]))

    audit = fixture[:tam_formula_adapter_audit]
    @test String(audit[:fitted_formulaA]) ==
        "~item + rater + item:step + psf"
    @test Int(audit[:n_design_rows]) == 20
    @test Int(audit[:n_score_categories]) == 4
    @test Int(audit[:n_independent_xsi]) == 22
    @test Int(audit[:n_expanded_xsi]) == 29
    @test Int(audit[:n_constraint_rows]) == 7
    @test Int(audit[:n_item_step_constraint_rows]) == 5
    @test Float64(audit[:rater_sum_abs]) <= 1e-10
    @test Float64(audit[:pseudo_facet_max_abs]) <= 1e-10
    @test Float64(audit[:item_step_sum_max_abs]) <= 1e-10
    @test Float64(audit[:category_intercept_reconstruction_max_abs_error]) <=
        1e-10

    summary = fixture[:summary]
    @test Bool(summary[:passed])
    @test Bool(summary[:tam_execution_completed])
    @test Bool(summary[:tam_parameter_table_extracted])
    @test Bool(summary[:parameter_comparison_completed])
    @test Bool(summary[:external_software_validation_completed]) == false
    @test Bool(summary[:public_claim_release_allowed]) == false
    @test Int(summary[:n_tam_parameter_rows]) == 29
    @test Int(summary[:n_item_rows]) == 5
    @test Int(summary[:n_rater_rows]) == 4
    @test Int(summary[:n_item_step_rows]) == 15
    @test Int(summary[:n_pseudo_facet_rows]) == 5
    @test Int(summary[:n_parameter_comparison_rows]) == 3
    @test Bool(summary[:formula_adapter_audit_completed])
    @test String(summary[:next_gate]) ==
        "freeze_prospective_tam_thresholds_and_run_multireplication_comparison"
end

function check_mgmfrm_tam_comparison_policy_review_fixture(
        fixture_path::AbstractString)
    root = dirname(dirname(@__DIR__))
    resolved_fixture_path =
        isabspath(fixture_path) ? fixture_path : joinpath(root, fixture_path)
    fixture = JSON3.read(read(resolved_fixture_path, String))
    @test String(fixture[:schema]) ==
        "bayesianmgmfrm.mgmfrm_tam_comparison_policy_review.v1"
    @test String(fixture[:family]) == "mfrm"
    @test String(fixture[:scope]) ==
        "tam_comparison_policy_and_item_step_adapter_review"
    @test String(fixture[:status]) ==
        "prospective_thresholds_frozen_adapter_structure_confirmed"
    @test String(fixture[:decision]) ==
        "run_multireplication_tam_comparison_keep_external_claim_blocked"
    @test Bool(fixture[:local_only])
    @test String(fixture[:external_software]) == "tam"
    @test Bool(fixture[:external_software_validation_completed]) == false
    @test Bool(fixture[:public_claim_release_allowed]) == false
    @test Bool(fixture[:publication_or_registration_action]) == false

    protocol = fixture[:protocol]
    @test String(protocol[:protocol_id]) ==
        "mgmfrm_tam_comparison_policy_review_v1"
    @test String(protocol[:generator]) ==
        "scripts/generate_mgmfrm_tam_comparison_policy_review.jl"
    @test String(protocol[:generator_source_sha256]) == file_sha256(joinpath(
        root, String(protocol[:generator])))
    for key in (:baseline_artifact, :execution_artifact)
        path = joinpath(root, String(protocol[key]))
        @test isfile(path)
        @test String(protocol[Symbol(String(key) * "_sha256")]) ==
            file_sha256(path)
    end
    @test String(protocol[:threshold_freeze_order]) ==
        "after_initial_pilot_before_multireplication_execution"
    @test String(protocol[:current_pilot_role]) ==
        "retrospective_calibration_only"
    @test String(protocol[:future_runs_role]) ==
        "prospective_confirmatory_gate"
    @test Float64(protocol[:structural_tolerance]) == 1e-10

    relationship = fixture[:relationship_to_tam]
    @test String(relationship[:overlapping_model]) ==
        "unidimensional_many_facet_rasch_partial_credit"
    @test Set(String.(relationship[:shared_terms])) == Set([
        "person_location", "item_difficulty", "rater_severity",
        "item_specific_category_steps",
    ])
    @test String(relationship[:estimator_difference]) ==
        "tam_marginal_maximum_likelihood_vs_package_bayesian_posterior"
    @test String(relationship[:current_comparison_target]) ==
        "known_truth_recovery_not_direct_estimate_equality"
    @test "multidimensional_fixed_q_loading" in
        String.(relationship[:excluded_generalizations])

    adapter = fixture[:item_step_adapter]
    @test String(adapter[:mapping]) ==
        "same_item_and_adjacent_step_after_tam_constraint_expansion"
    @test Bool(adapter[:structure_review_completed])
    @test Bool(adapter[:numerical_precision_review_completed]) == false

    structural = fixture[:structural_check_rows]
    @test length(structural) == 10
    @test all(row -> Bool(row[:passed]), structural)
    @test any(row -> String(row[:check]) ==
        "category_intercept_reconstruction" &&
        Float64(row[:observed]) <= 1e-10, structural)
    @test any(row -> String(row[:check]) == "item_step_sum_by_item" &&
        Float64(row[:observed]) <= 1e-10, structural)

    thresholds = fixture[:numerical_threshold_rows]
    @test length(thresholds) == 9
    @test count(row -> Bool(row[:passed]), thresholds) == 7
    @test all(row -> String(row[:evaluation_role]) ==
        "retrospective_pilot_calibration_only", thresholds)
    @test all(row -> String(row[:future_role]) ==
        "prospective_multireplication_gate", thresholds)
    @test count(row -> String(row[:block]) == "item_step" &&
        Bool(row[:passed]) == false, thresholds) == 2

    blocks = fixture[:block_decision_rows]
    @test length(blocks) == 3
    @test all(row -> Bool(row[:all_pilot_thresholds_passed]),
        filter(row -> String(row[:block]) in
            ("item_difficulty", "rater_severity"), blocks))
    item_step = only(row for row in blocks if String(row[:block]) == "item_step")
    @test Bool(item_step[:all_pilot_thresholds_passed]) == false
    @test String(item_step[:interpretation]) ==
        "adapter_structure_confirmed_but_pilot_precision_below_future_gate"

    @test Set(String.(fixture[:claim_limits])) == Set([
        "thresholds_frozen_after_first_pilot_not_before_it",
        "single_pilot_cannot_confirm_external_software_agreement",
        "item_step_pilot_misses_future_correlation_and_mean_absolute_difference_gates",
        "future_multireplication_results_required",
        "no_facets_or_conquest_execution",
        "no_generalized_gmfrm_or_mgmfrm_external_validation",
        "no_public_claim_release",
    ])

    summary = fixture[:summary]
    @test Bool(summary[:passed])
    @test Bool(summary[:structural_adapter_checks_passed])
    @test Bool(summary[:prospective_thresholds_frozen])
    @test Bool(summary[:current_pilot_all_numerical_thresholds_passed]) == false
    @test Bool(summary[:current_pilot_item_and_rater_thresholds_passed])
    @test Bool(summary[:current_pilot_item_step_thresholds_passed]) == false
    @test Int(summary[:n_structural_checks]) == 10
    @test Int(summary[:n_structural_checks_passed]) == 10
    @test Int(summary[:n_numerical_thresholds]) == 9
    @test Int(summary[:n_numerical_thresholds_passed]) == 7
    @test Bool(summary[:external_software_validation_completed]) == false
    @test Bool(summary[:public_claim_release_allowed]) == false
    @test String(summary[:next_gate]) ==
        "run_predeclared_multireplication_tam_comparison"
end

function check_mgmfrm_tam_multireplication_comparison_fixture(
        fixture_path::AbstractString)
    root = dirname(dirname(@__DIR__))
    resolved_fixture_path =
        isabspath(fixture_path) ? fixture_path : joinpath(root, fixture_path)
    fixture = JSON3.read(read(resolved_fixture_path, String))
    @test String(fixture[:schema]) ==
        "bayesianmgmfrm.mgmfrm_tam_multireplication_comparison.v1"
    @test String(fixture[:family]) == "mfrm"
    @test String(fixture[:scope]) ==
        "tam_predeclared_multireplication_known_truth_comparison"
    @test String(fixture[:status]) ==
        "tam_multireplication_comparison_recorded"
    @test String(fixture[:decision]) ==
        "record_tam_multireplication_gate_pass_keep_broad_claim_blocked"
    @test Bool(fixture[:local_only])
    @test String(fixture[:external_software]) == "tam"
    @test Bool(fixture[:tam_multireplication_execution_completed])
    @test Bool(fixture[:package_estimator_direct_comparison_completed]) == false
    @test Bool(fixture[:external_software_validation_completed]) == false
    @test Bool(fixture[:public_claim_release_allowed]) == false
    @test Bool(fixture[:publication_or_registration_action]) == false

    protocol = fixture[:protocol]
    @test String(protocol[:protocol_id]) ==
        "mgmfrm_tam_multireplication_comparison_v1"
    @test String(protocol[:generator]) ==
        "scripts/generate_mgmfrm_tam_multireplication_comparison.jl"
    @test String(protocol[:generator_source_sha256]) == file_sha256(joinpath(
        root, String(protocol[:generator])))
    for key in (:baseline_artifact, :policy_artifact)
        path = joinpath(root, String(protocol[key]))
        @test isfile(path)
        @test String(protocol[Symbol(String(key) * "_sha256")]) ==
            file_sha256(path)
    end
    @test Bool(protocol[:inherited_thresholds_unchanged])
    @test Int(protocol[:base_seed]) == 20260712
    @test Int.(protocol[:person_counts]) == [40, 100, 250]
    @test Int(protocol[:replications_per_person_count]) == 10
    @test Int(protocol[:primary_person_count]) == 250
    @test Float64(protocol[:primary_block_pass_rate_threshold]) == 0.80
    @test String(protocol[:primary_gate]) ==
        "each_parameter_block_all_metric_pass_rate_at_least_0_80"

    environment = fixture[:tam_environment]
    @test occursin("R version", String(environment[:r_version]))
    @test occursin(r"^[0-9]+\.[0-9]+\.[0-9]+$",
        String(environment[:tam_version]))
    @test !isempty(String(environment[:rscript_path]))

    scope = fixture[:relationship_scope]
    @test String(scope[:comparison]) ==
        "tam_estimates_against_shared_known_truth"
    @test Bool(scope[:direct_package_posterior_vs_tam_estimate_comparison]) ==
        false
    @test Bool(scope[:generalized_gmfrm_or_mgmfrm_scope]) == false

    replications = fixture[:replication_rows]
    @test length(replications) == 30
    @test Set(Int(row[:n_persons]) for row in replications) ==
        Set([40, 100, 250])
    @test all(n -> count(row -> Int(row[:n_persons]) == n, replications) == 10,
        (40, 100, 250))
    @test length(unique(Int(row[:ability_seed]) for row in replications)) == 30
    @test length(unique(Int(row[:response_seed]) for row in replications)) == 30
    @test all(row -> Int(row[:n_observations]) ==
        20 * Int(row[:n_persons]), replications)
    @test all(row -> Bool(row[:all_categories_observed]), replications)
    @test all(row -> Int(row[:tam_iter]) > 0, replications)
    @test all(row -> isfinite(Float64(row[:tam_deviance])), replications)
    @test all(row -> Int(row[:tam_n_parameters]) == 19, replications)
    @test all(row -> occursin(r"^[0-9a-f]{64}$",
        String(row[:observation_csv_sha256])), replications)
    @test all(row -> length(row[:comparisons]) == 3, replications)
    @test all(row -> Set(String(comparison[:block])
            for comparison in row[:comparisons]) ==
        Set(["item_difficulty", "rater_severity", "item_step"]), replications)

    scenario_blocks = fixture[:scenario_block_summary_rows]
    @test length(scenario_blocks) == 9
    @test all(row -> Int(row[:n_replications]) == 10, scenario_blocks)
    @test all(row -> 0.0 <= Float64(row[:all_thresholds_pass_rate]) <= 1.0,
        scenario_blocks)
    primary = filter(row -> Bool(row[:primary_gate_row]), scenario_blocks)
    @test length(primary) == 3
    @test all(row -> Int(row[:n_persons]) == 250, primary)
    @test all(row -> Float64(row[:all_thresholds_pass_rate]) == 1.0, primary)
    @test all(row -> Bool(row[:primary_gate_passed]), primary)
    n40_item_step = only(row for row in scenario_blocks
        if Int(row[:n_persons]) == 40 && String(row[:block]) == "item_step")
    @test Float64(n40_item_step[:all_thresholds_pass_rate]) == 0.60
    n100_item_step = only(row for row in scenario_blocks
        if Int(row[:n_persons]) == 100 && String(row[:block]) == "item_step")
    @test Float64(n100_item_step[:all_thresholds_pass_rate]) == 1.0

    @test Set(String.(fixture[:claim_limits])) == Set([
        "known_truth_tam_recovery_only",
        "not_direct_bayesianmgmfrm_posterior_vs_tam_estimate_agreement",
        "fixed_item_rater_step_truth_single_design",
        "no_facets_or_conquest_execution",
        "no_generalized_gmfrm_or_mgmfrm_external_validation",
        "no_external_construct_validity_claim",
        "no_public_claim_release",
    ])

    summary = fixture[:summary]
    @test Bool(summary[:passed])
    @test Bool(summary[:all_tam_executions_valid])
    @test Bool(summary[:primary_multireplication_gate_passed])
    @test Int(summary[:n_scenarios]) == 3
    @test Int(summary[:n_replications]) == 30
    @test Int(summary[:n_parameter_comparison_rows]) == 90
    @test Int(summary[:n_primary_block_rows]) == 3
    @test Int(summary[:n_primary_block_rows_passed]) == 3
    @test Bool(summary[:package_estimator_direct_comparison_completed]) == false
    @test Bool(summary[:external_software_validation_completed]) == false
    @test Bool(summary[:public_claim_release_allowed]) == false
    @test String(summary[:next_gate]) ==
        "compare_package_posterior_summaries_directly_with_tam_estimates"
end

function check_mgmfrm_tam_direct_estimate_pilot_fixture(
        fixture_path::AbstractString)
    root = dirname(dirname(@__DIR__))
    resolved_fixture_path =
        isabspath(fixture_path) ? fixture_path : joinpath(root, fixture_path)
    fixture = JSON3.read(read(resolved_fixture_path, String))
    @test String(fixture[:schema]) ==
        "bayesianmgmfrm.mgmfrm_tam_direct_estimate_pilot.v1"
    @test String(fixture[:family]) == "mfrm"
    @test String(fixture[:scope]) ==
        "tam_direct_package_posterior_estimate_pilot"
    @test String(fixture[:status]) ==
        "direct_estimate_pilot_recorded_thresholds_not_predeclared"
    @test String(fixture[:decision]) ==
        "record_descriptive_direct_comparison_keep_claim_blocked"
    @test Bool(fixture[:local_only])
    @test String(fixture[:external_software]) == "tam"
    @test Bool(fixture[:package_estimator_direct_comparison_completed])
    @test Bool(fixture[:direct_agreement_thresholds_predeclared]) == false
    @test Bool(fixture[:external_software_validation_completed]) == false
    @test Bool(fixture[:public_claim_release_allowed]) == false
    @test Bool(fixture[:publication_or_registration_action]) == false

    protocol = fixture[:protocol]
    @test String(protocol[:protocol_id]) ==
        "mgmfrm_tam_direct_estimate_pilot_v1"
    @test String(protocol[:generator]) ==
        "scripts/generate_mgmfrm_tam_direct_estimate_pilot.jl"
    @test String(protocol[:generator_source_sha256]) == file_sha256(joinpath(
        root, String(protocol[:generator])))
    for key in (:baseline_artifact, :tam_execution_review)
        path = joinpath(root, String(protocol[key]))
        @test isfile(path)
        @test String(protocol[Symbol(String(key) * "_sha256")]) ==
            file_sha256(path)
    end
    @test String(protocol[:package_fit]) ==
        "BayesianMGMFRM_AdvancedHMC_NUTS"
    @test Int(protocol[:seed]) == 20260713
    @test Int(protocol[:ndraws_per_chain]) == 400
    @test Int(protocol[:warmup_per_chain]) == 400
    @test Int(protocol[:chains]) == 4
    @test Float64(protocol[:target_accept]) == 0.90
    @test Int(protocol[:max_depth]) == 10
    @test String(protocol[:metric]) == "diagonal"
    @test String(protocol[:ad_backend]) == "ForwardDiff"

    crosswalk = fixture[:estimand_crosswalk]
    @test String(crosswalk[:item]) ==
        "center_reference_coded_package_and_tam_item_effects"
    @test String(crosswalk[:rater]) ==
        "center_reference_coded_package_and_tam_rater_effects"
    @test String(crosswalk[:item_step]) ==
        "reconstruct_last_step_as_negative_free_step_sum"
    @test Bool(crosswalk[:equality_expected]) == false

    sampler = fixture[:sampler_summary]
    @test Int(sampler[:n_parameters]) == 57
    @test Int(sampler[:total_posterior_draws]) == 1600
    @test Bool(sampler[:all_draws_and_logposterior_finite])
    @test 0.0 < Float64(sampler[:acceptance_rate]) < 1.0
    @test length(sampler[:chain_acceptance_rate]) == 4
    @test Int(sampler[:n_divergences]) == 0
    @test Int(sampler[:n_max_treedepth]) == 0
    @test Float64(sampler[:max_classical_split_rhat]) <= 1.01
    @test Float64(sampler[:min_autocorrelation_ess]) >= 400.0
    @test Int(sampler[:n_mcmc_warning_parameters]) == 0
    @test Bool(sampler[:manuscript_diagnostic_thresholds_passed])

    parameters = fixture[:parameter_rows]
    @test length(parameters) == 24
    @test count(row -> String(row[:block]) == "item_difficulty", parameters) == 5
    @test count(row -> String(row[:block]) == "rater_severity", parameters) == 4
    @test count(row -> String(row[:block]) == "item_step", parameters) == 15
    @test all(row -> isfinite(Float64(row[:package_posterior_mean])) &&
        Float64(row[:package_posterior_lower95]) <=
            Float64(row[:package_posterior_mean]) <=
            Float64(row[:package_posterior_upper95]), parameters)

    comparisons = fixture[:direct_comparison_rows]
    @test length(comparisons) == 6
    @test Set(String(row[:block]) for row in comparisons) ==
        Set(["item_difficulty", "rater_severity", "item_step"])
    tam_comparisons = filter(row -> occursin("tam_estimate",
        String(row[:interpretation])), comparisons)
    @test length(tam_comparisons) == 3
    @test all(row -> Float64(row[:pearson_correlation]) > 0.99,
        tam_comparisons)
    @test all(row -> Float64(row[:mean_abs_difference]) < 0.05,
        tam_comparisons)
    @test all(row -> Float64(row[:max_abs_difference]) < 0.15,
        tam_comparisons)

    intervals = fixture[:block_interval_summary_rows]
    @test length(intervals) == 3
    @test all(row -> Float64(row[:tam_inside_package_interval95_rate]) == 1.0,
        intervals)
    @test all(row -> 0.0 <= Float64(row[:truth_inside_package_interval95_rate]) <=
        1.0, intervals)

    @test Set(String.(fixture[:claim_limits])) == Set([
        "single_dataset_direct_estimate_pilot",
        "direct_agreement_thresholds_not_predeclared",
        "package_and_tam_estimators_are_not_identical",
        "package_uses_fixed_person_parameters_tam_uses_marginal_likelihood",
        "no_facets_or_conquest_execution",
        "no_generalized_gmfrm_or_mgmfrm_external_validation",
        "no_public_claim_release",
    ])

    summary = fixture[:summary]
    @test Bool(summary[:passed])
    @test Bool(summary[:direct_estimate_pilot_completed])
    @test Bool(summary[:direct_agreement_thresholds_predeclared]) == false
    @test Bool(summary[:sampler_diagnostics_passed])
    @test Int(summary[:n_parameter_rows]) == 24
    @test Int(summary[:n_direct_comparison_rows]) == 6
    @test Bool(summary[:external_software_validation_completed]) == false
    @test Bool(summary[:public_claim_release_allowed]) == false
    @test String(summary[:next_gate]) ==
        "freeze_direct_agreement_policy_then_run_multireplication_package_vs_tam_fits"
end

function check_mgmfrm_tam_direct_agreement_policy_fixture(
        fixture_path::AbstractString)
    root = dirname(dirname(@__DIR__))
    resolved_fixture_path =
        isabspath(fixture_path) ? fixture_path : joinpath(root, fixture_path)
    fixture = JSON3.read(read(resolved_fixture_path, String))
    @test String(fixture[:schema]) ==
        "bayesianmgmfrm.mgmfrm_tam_direct_agreement_policy.v1"
    @test String(fixture[:family]) == "mfrm"
    @test String(fixture[:scope]) ==
        "tam_direct_package_vs_tam_agreement_policy"
    @test String(fixture[:status]) ==
        "prospective_direct_agreement_policy_frozen"
    @test String(fixture[:decision]) ==
        "run_multireplication_package_vs_tam_fits_keep_claim_blocked"
    @test Bool(fixture[:local_only])
    @test String(fixture[:external_software]) == "tam"
    @test Bool(fixture[:direct_agreement_thresholds_predeclared])
    @test Bool(fixture[:future_direct_multireplication_execution_completed]) ==
        false
    @test Bool(fixture[:external_software_validation_completed]) == false
    @test Bool(fixture[:public_claim_release_allowed]) == false
    @test Bool(fixture[:publication_or_registration_action]) == false

    protocol = fixture[:protocol]
    @test String(protocol[:protocol_id]) ==
        "mgmfrm_tam_direct_agreement_policy_v1"
    @test String(protocol[:generator]) ==
        "scripts/generate_mgmfrm_tam_direct_agreement_policy.jl"
    @test String(protocol[:generator_source_sha256]) == file_sha256(joinpath(
        root, String(protocol[:generator])))
    @test String(protocol[:direct_estimate_pilot]) ==
        "test/fixtures/mgmfrm_tam_direct_estimate_pilot.json"
    @test String(protocol[:direct_estimate_pilot_sha256]) ==
        file_sha256(joinpath(root, String(protocol[:direct_estimate_pilot])))
    @test String(protocol[:threshold_freeze_order]) ==
        "after_single_dataset_direct_pilot_before_direct_multireplication_execution"
    @test String(protocol[:current_pilot_role]) ==
        "retrospective_calibration_only"
    @test String(protocol[:future_runs_role]) == "prospective_confirmatory_gate"

    relationship = fixture[:relationship_to_tam]
    @test String(relationship[:overlap_target]) ==
        "many_facet_rasch_partial_credit"
    @test String(relationship[:compared_estimand]) ==
        "aligned_item_rater_and_item_step_parameter_summaries"
    @test String(relationship[:package_estimator]) ==
        "bayesian_fixed_person_advancedhmc_posterior_mean_and_interval"
    @test String(relationship[:tam_estimator]) ==
        "marginal_maximum_likelihood_xsi_estimate"
    @test Bool(relationship[:exact_estimator_equality_expected]) == false

    plan = fixture[:future_execution_plan]
    @test String(plan[:planned_artifact]) ==
        "test/fixtures/mgmfrm_tam_direct_agreement_multireplication.json"
    @test Int.(plan[:person_counts]) == [40, 100]
    @test Int(plan[:replications_per_person_count]) == 5
    @test Int(plan[:primary_person_count]) == 100
    @test Float64(plan[:primary_block_pass_rate_threshold]) == 0.80
    @test Int(plan[:chains]) == 4
    @test Int(plan[:ndraws_per_chain]) == 400
    @test Int(plan[:warmup_per_chain]) == 400
    @test Float64(plan[:target_accept]) == 0.90
    @test String(plan[:gate]) ==
        "each_primary_block_all_direct_metrics_pass_rate_at_least_0_80_and_all_sampler_gates_pass"

    thresholds = fixture[:direct_threshold_rows]
    @test length(thresholds) == 12
    @test Set(String(row[:block]) for row in thresholds) ==
        Set(["item_difficulty", "rater_severity", "item_step"])
    @test all(row -> String(row[:evaluation_role]) ==
        "descriptive_pilot_calibration_only", thresholds)
    @test all(row -> String(row[:future_role]) ==
        "prospective_multireplication_gate", thresholds)
    @test all(row -> Bool(row[:pilot_passed]), thresholds)
    expected_thresholds = Dict(
        "pearson_correlation" => 0.95,
        "mean_abs_difference" => 0.10,
        "max_abs_difference" => 0.30,
        "tam_inside_package_interval95_rate" => 0.80,
    )
    @test Set(String(row[:metric]) for row in thresholds) ==
        Set(keys(expected_thresholds))
    @test all(row -> Float64(row[:threshold]) ==
        expected_thresholds[String(row[:metric])], thresholds)

    sampler = fixture[:sampler_threshold_rows]
    @test length(sampler) == 6
    @test all(row -> Bool(row[:pilot_passed]), sampler)
    @test all(row -> String(row[:future_role]) ==
        "prospective_fit_diagnostic_gate", sampler)
    @test any(row -> String(row[:metric]) == "max_classical_split_rhat" &&
        Float64(row[:threshold]) == 1.01, sampler)
    @test any(row -> String(row[:metric]) == "min_autocorrelation_ess" &&
        Float64(row[:threshold]) == 400.0, sampler)
    @test any(row -> String(row[:metric]) == "n_divergences" &&
        Int(row[:threshold]) == 0, sampler)

    blocks = fixture[:block_policy_rows]
    @test length(blocks) == 3
    @test all(row -> Int(row[:n_thresholds]) == 4, blocks)
    @test all(row -> Int(row[:n_pilot_thresholds_passed]) == 4, blocks)
    @test all(row -> Bool(row[:all_pilot_thresholds_passed]), blocks)

    @test Set(String.(fixture[:claim_limits])) == Set([
        "thresholds_frozen_after_single_direct_pilot_not_before_it",
        "current_pilot_is_calibration_only",
        "future_multireplication_package_vs_tam_fits_required",
        "package_and_tam_estimators_are_not_identical",
        "no_facets_or_conquest_execution",
        "no_generalized_gmfrm_or_mgmfrm_external_validation",
        "no_public_claim_release",
    ])

    summary = fixture[:summary]
    @test Bool(summary[:passed])
    @test Bool(summary[:direct_agreement_thresholds_predeclared])
    @test Bool(summary[:current_pilot_all_direct_thresholds_passed])
    @test Bool(summary[:current_pilot_all_sampler_thresholds_passed])
    @test Bool(summary[:future_direct_multireplication_execution_completed]) ==
        false
    @test Bool(summary[:external_software_validation_completed]) == false
    @test Bool(summary[:public_claim_release_allowed]) == false
    @test Int(summary[:n_direct_threshold_rows]) == 12
    @test Int(summary[:n_sampler_threshold_rows]) == 6
    @test Int(summary[:n_block_policy_rows]) == 3
    @test String(summary[:next_gate]) ==
        "run_predeclared_multireplication_package_vs_tam_direct_agreement"
end
