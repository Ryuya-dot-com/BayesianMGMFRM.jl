include("../test_group_selection.jl")
include("../intended_category_scale.jl")
include("../calibration_plot_data.jl")
include("../score_information.jl")
ScoreInformationChecks.checks(mktempdir())
@testset "optional research fixture boundary" begin
    fixture_env = "MFRM_TEST_OPTIONAL_RESEARCH_FIXTURE"
    withenv(fixture_env => nothing) do
        @test isempty(optional_fixture_path(
            fixture_env,
            joinpath("test", "fixtures", "not-present.json"),
        ))
    end
    withenv(fixture_env => "") do
        @test isempty(optional_fixture_path(
            fixture_env,
            joinpath("test", "fixtures", "not-present.json"),
        ))
    end
    mktemp() do fixture_path, io
        close(io)
        withenv(fixture_env => fixture_path) do
            if RUN_RESEARCH_EVIDENCE_TESTS
                @test optional_fixture_path(
                    fixture_env,
                    joinpath("test", "fixtures", "not-present.json"),
                ) == fixture_path
            else
                message = argument_error_message() do
                    optional_fixture_path(
                        fixture_env,
                        joinpath("test", "fixtures", "not-present.json"),
                    )
                end
                @test occursin("optional research-evidence fixture", message)
                @test occursin("BAYESIANMGMFRM_RESEARCH_EVIDENCE_TESTS=true", message)
            end
        end
    end
end

@testset "local JSON writer handles JSON3 dictionaries" begin
    source = JSON3.read("{\"z\":null,\"b\":[2,1],\"a\":{\"x\":true}}")
    io = IOBuffer()
    write_json(io, source)
    written = String(take!(io))
    reparsed = JSON3.read(written)
    @test reparsed[:z] === nothing
    @test Int.(reparsed[:b]) == [2, 1]
    @test Bool(reparsed[:a][:x])
    @test first(findfirst("\"a\"", written)) <
        first(findfirst("\"b\"", written)) <
        first(findfirst("\"z\"", written))
    canonical_io = IOBuffer()
    write_canonical_json(canonical_io, (;
        z = -0.0,
        b = 1000.0,
        a = (value = 4.0, ratio = 0.75),
    ))
    canonical_written = String(take!(canonical_io))
    canonical_reparsed = JSON3.read(canonical_written)
    reparsed_io = IOBuffer()
    write_canonical_json(reparsed_io, canonical_reparsed)
    @test String(take!(reparsed_io)) == canonical_written
    @test canonical_written ==
        "{\"a\":{\"ratio\":0.75,\"value\":4},\"b\":1000,\"z\":0}"

    raw_error = "MethodError: no method matching fit(::Any; experimental=true)\r\n" *
        "Closest candidates are:\r\n" *
        "  fit(::Any; experimental)\r\n" *
        "    @ BayesianMGMFRM /Users/example/src/bayesian_fit.jl:1071\r" *
        "  fit(::Any) got unsupported keyword argument \"experimental\"\r\n" *
        "    @ BayesianMGMFRM C:\\workspace\\src\\bayesian_fit.jl:3114"
    normalized_error = normalize_error_message(raw_error)
    @test occursin("fit(::Any; experimental)", normalized_error)
    @test occursin("unsupported keyword argument \"experimental\"",
        normalized_error)
    @test !occursin('\r', normalized_error)
    @test !occursin("/Users/example", normalized_error)
    @test !occursin("C:\\workspace", normalized_error)
    @test !occursin(r"\.jl:\d+", normalized_error)

    fixture_root = joinpath(dirname(@__DIR__), "fixtures")
    location_pattern = r"\.jl:\d+"
    location_bearing_fixtures = sort!(String[
        relpath(path, dirname(dirname(@__DIR__)))
        for path in readdir(fixture_root; join = true)
        if endswith(path, ".json") &&
            occursin(location_pattern, read(path, String))
    ])
    @test isempty(location_bearing_fixtures)
end

@testset "root API classification and docstrings" begin
    contract = BayesianMGMFRM._root_api_contract()
    @test contract.schema == "bayesianmgmfrm.root_api_contract.v2"
    @test contract.release_line == "0.2.x"
    @test contract.growth_policy === :curated_layer1
    @test contract.owner === :package_maintainers
    @test contract.manual_policy == (;
        layer1_practitioner = :required,
        glass_box = :documented_layer2,
        validation_suite = :optional_explicitly_nonstable,
        legacy = :compatibility_migration,
    )

    groups = (contract.layer1_practitioner, contract.glass_box, contract.validation_suite, contract.legacy)
    @test all(group -> all(name -> name isa Symbol, group), groups)
    @test all(group -> length(group) == length(unique(group)), groups)
    @test all(group -> issorted(group; by = String), groups)
    @test isempty(intersect(Set(contract.layer1_practitioner), Set(contract.glass_box)))
    @test isempty(intersect(Set(contract.layer1_practitioner), Set(contract.validation_suite)))
    @test isempty(intersect(Set(contract.layer1_practitioner), Set(contract.legacy)))

    exported = Set(names(BayesianMGMFRM;
        all = false,
        imported = false,
    ))
    delete!(exported, :BayesianMGMFRM)
    @test exported == Set(contract.layer1_practitioner)
    @test all(name -> has_doc(BayesianMGMFRM, name), contract.layer1_practitioner)
    @test all(name -> has_doc(BayesianMGMFRM, name), contract.legacy)
end

@testset "representative public docstrings" begin
    for name in (:FacetData, :ValidationIssue, :ValidationReport, :FacetSpec, :FacetDesign,
            :CmdStanError,
            :MFRMPrior, :MFRMLogDensity, :MFRMFit, :GMFRMFit, :MGMFRMFit,
            :anchor_linking_summary, :artifact_content_hash, :cached_fit,
            :benchmark_result_row, :benchmark_summary, :calibration_plot_data,
            :case_study_provenance_manifest,
            :cmdstan_backend_contract, :cmdstan_backend_check,
            :constraint_table, :dff_report, :domain_compilation_summary,
            :conquest_bridge_bundle, :facets_bridge_bundle,
            :external_bridge_result_receipt,
            :expected_scores, :facets_compatibility_stats, :facets_report,
            :fair_average_summary,
            :falsification_rule_summary, :falsification_rules,
            :fit, :fit_archive_manifest, :fit_artifact, :fit_cache_key, :fit_metadata,
            :fit_reproduction_manifest,
            :fit_ready_parameter_layout, :fit_stats,
            :identification_declarations,
            :initial_params, :loglikelihood, :logposterior, :logprior,
            :kfold, :loo, :psis_loo, :loo_diagnostics,
            :linear_predictor_table, :linear_predictor_values,
            :local_dependence_contract, :local_dependence_summary,
            :calibration_table, :diagnostics,
            :diagnostic_map_data,
            :comparison_evidence_row, :comparison_evidence_summary,
            :compare_kfold, :compare_models, :coverage_matrix, :coverage_summary, :design_row_table, :validate_design, :mcmc_diagnostics, :mfrm_spec, :getdesign,
            :model_equation, :model_ladder, :model_manifest, :model_surface_audit,
            :parameter_block_diagnostics,
            :parameter_recovery, :parameter_recovery_plot_data, :parameter_recovery_summary,
            :pointwise_loglikelihood, :pointwise_loglikelihood_matrix, :posterior_predict,
            :posterior_predictive_check, :posterior_summary,
            :predictive_check_summary, :predictive_check_plot_data, :predictive_probabilities,
            :predictive_residuals, :predictive_standardized_residuals,
            :predictive_variances,
            :prior_likelihood_sensitivity, :prior_predict, :prior_predictive_check,
            :q_matrix_validation,
            :fit_report_dossier, :fit_report_dossier_markdown,
            :fit_report_health,
            :fit_report_markdown, :fit_report_section, :fit_report_sections,
            :fit_report_rows,
            :load_fit_cache, :load_fit_report, :load_fit_report_dossier,
            :load_fit_report_bundle,
            :load_fit_report_tables, :load_conquest_parameter_export,
            :rater_diagnostics, :rater_overlap,
            :rating_design_audit,
            :related_software_capability_matrix, :release_gate_check,
            :release_scope_summary, :residual_summary, :sampler_diagnostics,
            :save_fit_cache, :save_fit_report,
            :save_fit_report_dossier, :save_fit_report_dossier_markdown,
            :save_fit_report_bundle, :save_fit_report_markdown,
            :save_fit_report_tables,
            :save_external_bridge_bundle,
            :sensitivity_comparison, :sensitivity_comparison_summary,
            :separation_reliability_summary, :simulation_grid,
            :simulation_grid_summary, :simulate_responses,
            :stan_validation_row, :stan_validation_summary,
            :testlet_design_audit, :threshold_map_data, :validation_suggestions,
            :validate_external_bridge_bundle,
            :evidence_metadata,
            :evidence_artifact_schema_policy,
            :waic, :waic_diagnostics, :wright_map_data)
        @test has_doc(BayesianMGMFRM, name)
    end
    @test !isdefined(BayesianMGMFRM, :audit)
    @test !isdefined(BayesianMGMFRM, :AuditIssue)
    @test !isdefined(BayesianMGMFRM, :AuditReport)
end

include("../cmdstan_backend.jl")
include("../cmdstan_validation_contract.jl")
test_flag("BAYESIANMGMFRM_CMDSTAN_TESTS") &&
    include("../cmdstan_sampling.jl")
test_flag("BAYESIANMGMFRM_CMDSTAN_TESTS") &&
    include("../cmdstan_adaptation_sampling.jl")
test_flag("BAYESIANMGMFRM_CMDSTAN_PAIRED_TESTS") &&
    include("../cmdstan_paired_validation.jl")
test_flag("BAYESIANMGMFRM_CMDSTAN_RECOVERY_PILOT_TESTS") &&
    include("../cmdstan_recovery_pilot.jl")

@testset "FacetData long-format indexing" begin
    table = (
        examinee = ["E2", "E1", "E1", "E2", "E1", "E2", "E2", "E1"],
        rater = ["R2", "R1", "R2", "R1", "R1", "R2", "R1", "R2"],
        item = ["I2", "I1", "I1", "I2", "I2", "I1", "I1", "I2"],
        score = [2, 0, 1, 1, 2, 0, 1, 2],
    )
    data = FacetData(table; person = :examinee, rater = :rater, item = :item, score = :score)

    @test length(data) == 8
    @test data.person_levels == Any["E1", "E2"]
    @test data.rater_levels == Any["R1", "R2"]
    @test data.item_levels == Any["I1", "I2"]
    @test data.category_levels == [0, 1, 2]
    @test data.person == [2, 1, 1, 2, 1, 2, 2, 1]
    response_table = facet_response_table(data)
    @test response_table == (;
        person = table.examinee,
        rater = table.rater,
        item = table.item,
        score = table.score,
    )
    selected_response_table = facet_response_table(data; observations = [2, 5, 1])
    @test selected_response_table == (;
        person = ["E1", "E1", "E2"],
        rater = ["R1", "R1", "R2"],
        item = ["I1", "I2", "I2"],
        score = [0, 2, 2],
    )
    selected_roundtrip = FacetData(selected_response_table;
        person = :person,
        rater = :rater,
        item = :item,
        score = :score)
    @test selected_roundtrip.person_levels == Any["E1", "E2"]
    @test selected_roundtrip.rater_levels == Any["R1", "R2"]
    @test selected_roundtrip.item_levels == Any["I1", "I2"]
    @test facet_response_table(data; observations = Int[]).score == Int[]
    @test_throws ArgumentError facet_response_table(data; observations = [1, 1])
    @test_throws ArgumentError facet_response_table(data; observations = [0])
    @test_throws ArgumentError facet_response_table(data; observations = [data.n + 1])
    @test_throws ArgumentError facet_response_table(data; observations = [true])

    reordered = (
        examinee = reverse(table.examinee),
        rater = reverse(table.rater),
        item = reverse(table.item),
        score = reverse(table.score),
    )
    data2 = FacetData(reordered; person = :examinee, rater = :rater, item = :item, score = :score)
    @test data2.person_levels == data.person_levels
    @test data2.rater_levels == data.rater_levels
    @test data2.item_levels == data.item_levels
    @test data2.category_levels == data.category_levels

    numeric_labels = (
        examinee = [1, 10, 2, 1],
        rater = ["R1", "R1", "R1", "R1"],
        item = ["I1", "I1", "I1", "I1"],
        score = [0, 1, 0, 1],
    )
    data3 = FacetData(numeric_labels; person = :examinee, rater = :rater, item = :item, score = :score)
    @test data3.person_levels == Any[1, 2, 10]

    optional_table = (
        examinee = ["E1", "E1", "E2", "E2"],
        rater = ["R1", "R2", "R1", "R2"],
        item = ["I1", "I2", "I1", "I2"],
        score = [0, 1, 1, 2],
        treatment = ["A", "A", "B", "B"],
        task_name = ["T1", "T2", "T1", "T2"],
    )
    optional_data = FacetData(optional_table;
        person = :examinee,
        rater = :rater,
        item = :item,
        score = :score,
        group = :treatment,
        task = :task_name)
    optional_response_table =
        facet_response_table(optional_data; observations = [4, 2])
    @test propertynames(optional_response_table) ==
        (:person, :rater, :item, :score, :group, :task)
    @test optional_response_table.person == ["E2", "E1"]
    @test optional_response_table.rater == ["R2", "R2"]
    @test optional_response_table.item == ["I2", "I2"]
    @test optional_response_table.score == [2, 1]
    @test optional_response_table.group == ["B", "A"]
    @test optional_response_table.task == ["T2", "T2"]

    bool_scores = (
        examinee = ["E1", "E1"],
        rater = ["R1", "R1"],
        item = ["I1", "I1"],
        score = [false, true],
    )
    @test_throws ArgumentError FacetData(bool_scores; person = :examinee, rater = :rater, item = :item, score = :score)

    @test_throws ErrorException FacetData(ExplodingTable(); person = :examinee, rater = :rater, item = :item, score = :score)
    @test_throws MethodError FacetData(InternalMethodErrorTable(); person = :examinee, rater = :rater, item = :item, score = :score)
    collection_error = argument_error_message() do
        FacetData(
            CollectionFailureTable();
            person = :examinee,
            rater = :rater,
            item = :item,
            score = :score,
        )
    end
    @test collection_error ==
        "ArgumentError: column storage not found during collection"
end

@testset "pre-fit validation" begin
    empty = (
        examinee = String[],
        rater = String[],
        item = String[],
        score = Int[],
    )
    empty_data = FacetData(empty; person = :examinee, rater = :rater, item = :item, score = :score)
    empty_report = validate_design(empty_data)
    @test !empty_report.passed
    @test has_issue(empty_report, :empty_data)

    connected = (
        examinee = ["E1", "E1", "E1", "E2", "E2", "E2"],
        rater = ["R1", "R2", "R1", "R1", "R2", "R1"],
        item = ["I1", "I1", "I2", "I1", "I2", "I2"],
        score = [0, 1, 2, 1, 0, 2],
    )
    connected_data = FacetData(connected; person = :examinee, rater = :rater, item = :item, score = :score)
    connected_report = validate_design(connected_data)
    @test connected_report.passed
    @test !has_issue(connected_report, :disconnected_design)
    @test !has_issue(connected_report, :rank_deficient_design)
    @test has_issue(connected_report, :unobserved_item_category)

    rank_deficient_connected = (
        examinee = ["E1", "E1", "E2", "E2"],
        rater = ["R1", "R2", "R2", "R1"],
        item = ["I1", "I1", "I2", "I2"],
        score = [0, 1, 2, 1],
    )
    rank_data = FacetData(rank_deficient_connected; person = :examinee, rater = :rater, item = :item, score = :score)
    rank_report = validate_design(rank_data)
    @test !rank_report.passed
    @test !has_issue(rank_report, :disconnected_design)
    @test has_issue(rank_report, :rank_deficient_design)
    @test_throws ArgumentError mfrm_spec(rank_data)

    disconnected = (
        examinee = ["E1", "E1", "E2", "E2"],
        rater = ["R1", "R1", "R2", "R2"],
        item = ["I1", "I1", "I2", "I2"],
        score = [0, 1, 0, 1],
    )
    disconnected_data = FacetData(disconnected; person = :examinee, rater = :rater, item = :item, score = :score)
    disconnected_report = validate_design(disconnected_data)
    @test !disconnected_report.passed
    @test has_issue(disconnected_report, :disconnected_design)
    @test_throws ArgumentError mfrm_spec(disconnected_data)

    skipped_category = (
        examinee = ["E1", "E1", "E1", "E2", "E2", "E2"],
        rater = ["R1", "R2", "R1", "R1", "R2", "R1"],
        item = ["I1", "I1", "I2", "I1", "I2", "I2"],
        score = [0, 2, 0, 2, 0, 2],
    )
    skipped_data = FacetData(skipped_category; person = :examinee, rater = :rater, item = :item, score = :score)
    skipped_report = validate_design(skipped_data)
    @test skipped_report.passed
    @test skipped_data.category_levels == [0, 1, 2]
    @test skipped_report.category_counts[1] == 0
    @test has_issue(skipped_report, :unused_interior_category)
    @test has_issue(skipped_report, :unobserved_item_category)

    optional_singleton = (
        examinee = ["E1", "E1", "E1", "E2", "E2", "E2"],
        rater = ["R1", "R2", "R1", "R1", "R2", "R1"],
        item = ["I1", "I1", "I2", "I1", "I2", "I2"],
        group = ["A", "A", "A", "A", "A", "B"],
        score = [0, 1, 2, 1, 0, 2],
    )
    optional_data = FacetData(optional_singleton;
        person = :examinee,
        rater = :rater,
        item = :item,
        score = :score,
        group = :group)
    optional_report = validate_design(optional_data)
    @test has_issue(optional_report, :singleton_facet_level, :group)

    dff_empty = (
        examinee = ["E1", "E1", "E1", "E2", "E2", "E2"],
        rater = ["R1", "R2", "R1", "R1", "R2", "R1"],
        item = ["I1", "I1", "I2", "I1", "I2", "I2"],
        group = ["A", "A", "A", "A", "B", "A"],
        score = [0, 1, 2, 1, 0, 2],
    )
    dff_data = FacetData(dff_empty;
        person = :examinee,
        rater = :rater,
        item = :item,
        score = :score,
        group = :group)
    dff_report = validate_design(dff_data; bias = [(:rater, :group)])
    @test dff_report.passed
    @test has_issue(dff_report, :empty_dff_cell)
    @test has_issue(dff_report, :potential_dff_confounding)
    @test dff_report.dff_counts[(:rater, :group)][("R1", "B")] == 0
    dff_suggestions = validation_suggestions(dff_report)
    @test any(row -> row.code === :empty_dff_cell && row.action === :pool_or_remove_dff_term,
        dff_suggestions)
    @test all(row -> haskey(row.context, :term) || row.code !== :empty_dff_cell,
        dff_suggestions)

    invalid_bias_report = validate_design(connected_data; bias = [:rater])
    @test !invalid_bias_report.passed
    @test has_issue(invalid_bias_report, :invalid_bias_term)
    invalid_bias_suggestion = only(filter(row -> row.code === :invalid_bias_term,
        validation_suggestions(invalid_bias_report)))
    @test invalid_bias_suggestion.action === :fix_bias_syntax

    unknown_bias_report = validate_design(connected_data; bias = [(:rater, :group)])
    @test !unknown_bias_report.passed
    @test has_issue(unknown_bias_report, :unknown_bias_facet)

    sparse_dff_report = validate_design(dff_data; bias = [(:rater, :group)], min_cell_count = 3)
    @test sparse_dff_report.passed
    @test has_issue(sparse_dff_report, :sparse_dff_cell)
    @test_throws ArgumentError validate_design(connected_data; min_cell_count = 0)
end

@testset "minimal MFRM spec and design" begin
    table = (
        examinee = ["E1", "E1"],
        rater = ["R1", "R1"],
        item = ["I1", "I1"],
        score = [0, 1],
    )
    data = FacetData(table; person = :examinee, rater = :rater, item = :item, score = :score)
    spec = mfrm_spec(data; thresholds = :partial_credit)
    design = getdesign(spec)

    ladder = model_ladder()
    @test any(row -> row.family === :mfrm && row.estimation_status === :fit_supported, ladder)
    @test any(row -> row.family === :gmfrm &&
        row.estimation_status === :experimental_public &&
        row.experimental_public,
        ladder)
    @test any(row -> row.family === :mgmfrm &&
        row.estimation_status === :experimental_public &&
        row.experimental_public,
        ladder)
    @test any(row -> row.family === :gmfrm && row.estimation_status === :specified_only, ladder)
    @test any(row -> row.family === :mgmfrm && row.estimation_status === :specified_only, ladder)
    release_scope = release_scope_summary()
    @test release_scope.schema == "bayesianmgmfrm.release_scope_summary.v1"
    @test any(row -> row.status === :supported &&
        :fit_supported in row.current_aliases,
        release_scope.status_vocabulary)
    @test any(row -> row.status === :experimental_public &&
        row.public_fit &&
        row.experimental_public &&
        :guarded_experimental in row.current_aliases,
        release_scope.status_vocabulary)
    @test any(row -> row.status === :blocked &&
        :out_of_scope in row.current_aliases &&
        :not_a_public_fit_api in row.current_aliases,
        release_scope.status_vocabulary)
    @test any(row -> row.status === :external_validated &&
        row.stable_public &&
        row.external_validated,
        release_scope.status_vocabulary)
    @test release_scope.summary.n_status_vocabulary_rows ==
        length(release_scope.status_vocabulary)
    external_policy = BayesianMGMFRM._status_policy_manifest(
        :mgmfrm,
        :fit_supported;
        public_fit = true,
        stable_public = true,
        external_validated = true,
        claim_scope = :post_v0_2_external_validation,
    )
    @test external_policy.status_label === :external_validated
    @test external_policy.stable_public
    @test !(:external_validation in external_policy.blocked_claims)
    @test !(:r_package_overlap_comparison in external_policy.blocked_claims)
    @test !(:real_data_validation in external_policy.blocked_claims)
    experimental_policy = BayesianMGMFRM._status_policy_manifest(
        :mgmfrm,
        :experimental_public;
        public_fit = true,
        experimental_public = true,
        fit_ready = true,
        claim_scope = :fixed_q_confirmatory_only,
    )
    @test experimental_policy.next_gate ===
        :v0_1_2_fixed_q_productionization
    evidence_policy = evidence_artifact_schema_policy(:unit_test;
        include_environment = false,
        raw_data_status = :not_included)
    @test evidence_policy.schema ==
        "bayesianmgmfrm.evidence_artifact_schema_policy.v1"
    @test evidence_policy.object === :evidence_artifact_schema_policy
    @test !evidence_policy.environment_policy.
        record_project_hash_when_available
    @test !evidence_policy.environment_policy.
        record_git_status_hash_when_available
    @test evidence_policy.environment_policy.allow_missing_git_checkout
    environment_included_policy = evidence_artifact_schema_policy(:unit_test)
    @test environment_included_policy.environment_policy.
        record_project_hash_when_available
    @test environment_included_policy.environment_policy.
        record_git_status_hash_when_available
    @test environment_included_policy.environment_policy.
        allow_missing_git_checkout
    @test evidence_policy.artifact_kind === :unit_test
    @test evidence_policy.hash_policy.algorithm === :sha256
    @test evidence_policy.scientific_payload_hash_policy.payload_field ===
        :scientific_payload
    @test evidence_policy.scientific_payload_hash_policy.digest_field ===
        :scientific_payload_sha256
    @test evidence_policy.scientific_payload_hash_policy.projection_policy ===
        :explicit_schema_contract
    @test evidence_policy.scientific_payload_hash_policy.implementation_scope ===
        :repository_tooling
    @test evidence_policy.scientific_payload_hash_policy.
        artifact_integration_status === :staged
    @test evidence_policy.scientific_payload_hash_policy.
        semantic_equivalence_comparison_status === :not_yet_integrated
    @test !evidence_policy.scientific_payload_hash_policy.
        legacy_absence_verifies_equivalence
    @test evidence_policy.scientific_payload_hash_policy.
        semantic_gate_requires_verified_digest
    @test evidence_policy.scientific_payload_hash_policy.
        exact_file_sha256_retained
    @test any(row -> row.field === :schema && row.status === :required,
        evidence_policy.required_fields)
    @test any(row -> row.field === :unsupported_claims,
        evidence_policy.required_fields)
    @test evidence_policy.execution_policy.require_cache_provenance_or_not_applicable
    @test !evidence_policy.claim_policy.public_model_weight_claims_allowed
    @test evidence_policy.raw_data_policy.status === :not_included
    metadata = evidence_metadata(; include_packages = false)
    @test haskey(metadata, "git")
    @test haskey(metadata, "hashes")
    @test haskey(metadata["hashes"], "active_project_sha256")
    @test haskey(metadata["hashes"], "manifest_sha256")
    @test isnothing(metadata["hashes"]["active_project_sha256"]) ||
        length(metadata["hashes"]["active_project_sha256"]) == 64
    @test metadata["hashes"]["active_project"] === nothing
    @test metadata["hashes"]["manifest"] === nothing
    @test metadata["software"]["julia"]["project"] === nothing
    @test metadata["software"]["julia"]["depot_path"] === nothing
    @test metadata["software"]["julia"]["load_path"] === nothing
    @test metadata["execution"]["power_thermal_notes"] === nothing
    git_metadata = metadata["git"]
    mktempdir() do directory
        cd(directory) do
            metadata_from_other_cwd = evidence_metadata(;
                include_packages = false,
            )
            @test metadata_from_other_cwd["git"] == git_metadata
        end
    end
    withenv("GMFRM_POWER_NOTES" => "/Users/example/private-notes.txt") do
        public_metadata = evidence_metadata(; include_packages = false)
        @test public_metadata["execution"]["power_thermal_notes"] === nothing
        @test public_metadata["execution"]["power_thermal_notes_recorded"]
        private_notes_metadata = evidence_metadata(;
            include_packages = false,
            include_paths = true,
        )
        @test private_notes_metadata["execution"]["power_thermal_notes"] ==
            "/Users/example/private-notes.txt"
    end
    private_metadata = evidence_metadata(;
        include_packages = false,
        include_paths = true,
    )
    @test private_metadata["hashes"]["active_project"] ==
        Base.active_project()
    mktempdir() do directory
        project = joinpath(directory, "Project.toml")
        write(project, "")
        generic = joinpath(directory, "Manifest.toml")
        versioned = joinpath(directory,
            "Manifest-v$(VERSION.major).$(VERSION.minor).toml")
        write(generic, "generic")
        @test BayesianMGMFRM._evidence_manifest_path(project) == generic
        write(versioned, "versioned")
        @test BayesianMGMFRM._evidence_manifest_path(project) ==
            (basename(versioned) in Base.manifest_names ? versioned : generic)
    end
    @test release_scope.evidence_artifact_schema_policy.schema ==
        evidence_policy.schema
    @test release_scope.evidence_artifact_schema_policy.artifact_kind ===
        :release_scope_evidence
    @test release_scope.summary.evidence_artifact_schema_policy_recorded
    @test release_scope.summary.related_software_capability_matrix_recorded
    capability_matrix = related_software_capability_matrix()
    @test capability_matrix.schema ==
        "bayesianmgmfrm.related_software_capability_matrix.v1"
    @test capability_matrix.object === :related_software_capability_matrix
    @test capability_matrix.status === :scope_positioning_recorded
    @test capability_matrix.summary.n_tools == 7
    @test capability_matrix.summary.no_superiority_claims
    @test !capability_matrix.summary.generic_irt_replacement_claims_allowed
    @test !capability_matrix.summary.r_package_overlap_comparison_allowed
    @test capability_matrix.summary.comparison_gate ===
        :post_v0_2_known_truth_simulation_where_overlap_exists
    @test all(tool -> tool in capability_matrix.summary.tools,
        (:facets, :tam, :mirt, :sirt, :immer, :brms_stan, :bayesianmgmfrm))
    tam_row = only(row for row in capability_matrix.rows if row.tool === :tam)
    @test :multi_faceted_rasch_models in tam_row.model_coverage
    @test tam_row.v0_1_1_position === :breadth_baseline_not_feature_checklist
    mirt_row = only(row for row in capability_matrix.rows if row.tool === :mirt)
    @test :multidimensional_irt in mirt_row.model_coverage
    @test mirt_row.rater_facet_support === :not_a_dedicated_mfrm_facets_workflow
    facets_row = only(row for row in capability_matrix.rows if row.tool === :facets)
    @test facets_row.rater_facet_support === :first_class_many_facet_rater_support
    immer_row = only(row for row in capability_matrix.rows if row.tool === :immer)
    @test immer_row.current_role === :models_for_multiple_ratings
    brms_row = only(row for row in capability_matrix.rows if row.tool === :brms_stan)
    @test brms_row.bayesian_support === :first_class_bayesian_inference
    package_row = only(row for row in capability_matrix.rows if row.tool === :bayesianmgmfrm)
    @test package_row.multidimensional_support ===
        :fixed_q_confirmatory_experimental_only
    @test package_row.v0_1_1_position ===
        :narrow_auditable_workflow_not_generic_irt_replacement
    @test release_scope.summary.n_public_fit_surfaces == 5
    @test release_scope.summary.n_guarded_experimental_surfaces == 4
    @test release_scope.summary.minimal_mfrm_fit_allowed
    @test release_scope.summary.scalar_gmfrm_guarded_fit_allowed
    @test release_scope.summary.fixed_q_mgmfrm_guarded_fit_allowed
    @test release_scope.summary.guarded_generalized_fit_cache_ready
    @test release_scope.summary.fit_reproduction_cache_identity_checked
    @test release_scope.summary.documenter_html_page_size_gate
    @test release_scope.summary.pre_registration_gate_available
    @test release_scope.summary.general_registration_manual_only
    @test !release_scope.summary.broader_generalized_fit_allowed
    @test !release_scope.summary.dff_model_effects_allowed
    @test !release_scope.summary.model_weight_claims_allowed
    @test !release_scope.summary.publication_or_registration_action
    @test release_scope.summary.development_version ==
        string(pkgversion(BayesianMGMFRM))
    @test release_scope.summary.development_phase ===
        :v0_1_2_fixed_q_productionization
    @test release_scope.summary.development_next_gate ===
        :v0_1_2_fixed_q_productionization
    @test release_scope.summary.v0_1_1_generalized_refinement_planned
    @test release_scope.summary.
        v0_1_1_generalized_refinement_planned_field_semantics ===
            :historical_plan_record_present
    @test release_scope.summary.v0_1_1_generalized_refinement_completed
    @test release_scope.summary.v0_1_1_generalized_refinement_status ===
        :completed
    @test isempty(release_scope.evidence_rows)
    @test release_scope.summary.n_progress_evidence_rows == 0
    @test all(row -> !(row.experimental_public && row.family in (:gmfrm, :mgmfrm)) ||
        (row.completed_gate === :v0_1_1_generalized_refinement &&
            row.next_gate === :v0_1_2_fixed_q_productionization),
        release_scope.public_fit_surfaces)
    @test any(row -> row.surface === :scalar_gmfrm_guarded_experimental &&
        row.entrypoint == "BayesianMGMFRM.Experimental.fit(spec)" &&
        row.legacy_entrypoint ==
            "BayesianMGMFRM.fit(spec; experimental = true)",
        release_scope.public_fit_surfaces)
    @test any(row -> row.family === :mgmfrm && row.option === :q_matrix &&
        row.status === :blocked,
        release_scope.blocked_public_options)
    @test any(row -> row.claim === :model_weight_or_superiority &&
        row.status === :blocked,
        release_scope.blocked_claims)
    @test any(row -> row.claim === :r_package_overlap_comparison &&
        row.status === :blocked,
        release_scope.blocked_claims)
    @test any(row -> row.claim === :real_data_validation &&
        row.status === :blocked,
        release_scope.blocked_claims)
    @test any(row -> row.claim === :external_validation &&
        row.status === :blocked,
        release_scope.blocked_claims)
    release_scope_with_evidence = release_scope_summary(; include_evidence = true)
    @test release_scope_with_evidence.summary.n_evidence_rows ==
        length(release_scope_with_evidence.evidence_rows)
    @test release_scope_with_evidence.summary.n_evidence_rows >
        release_scope.summary.n_evidence_rows
    progress_evidence_scopes = (
        :free_latent_correlation_operational_prerequisites,
        :free_latent_correlation_scientific_execution,
        :v0_1_2_ld1b_integration,
        :ld1b_scientific_execution,
    )
    progress_evidence_rows = Tuple(row
        for row in release_scope_with_evidence.evidence_rows
        if row.scope in progress_evidence_scopes)
    progress_evidence_required_fields = (
        :record_status,
        :gate_status,
        :execution_status,
        :numerator,
        :denominator,
        :attainment_percent,
        :denominator_kind,
        :counts_toward_scientific_denominator,
        :source_artifact,
    )
    @test length(progress_evidence_rows) == 4
    @test release_scope_with_evidence.summary.n_progress_evidence_rows == 4
    @test Set(row.scope for row in progress_evidence_rows) ==
        Set(progress_evidence_scopes)
    @test all(row -> all(field -> haskey(row, field),
            progress_evidence_required_fields), progress_evidence_rows)
    @test all(row -> !haskey(row, :status), progress_evidence_rows)
    @test all(row -> 0 <= row.numerator <= row.denominator,
        progress_evidence_rows)
    @test all(row -> row.attainment_percent == round(
            100 * row.numerator / row.denominator;
            digits = 1,
        ), progress_evidence_rows)
    @test all(row -> 0.0 <= row.attainment_percent <= 100.0,
        progress_evidence_rows)

    free_correlation_operational_progress = only(row
        for row in progress_evidence_rows
        if row.scope === :free_latent_correlation_operational_prerequisites)
    @test free_correlation_operational_progress.record_status ===
        :current_progress_recorded
    @test free_correlation_operational_progress.gate_status === :not_passed
    @test free_correlation_operational_progress.execution_status ===
        :mcmc_free_initial_gradient_profile_failed
    @test free_correlation_operational_progress.numerator == 0
    @test free_correlation_operational_progress.denominator == 3
    @test free_correlation_operational_progress.attainment_percent == 0.0
    @test free_correlation_operational_progress.denominator ==
        length(free_correlation_operational_progress.gate_rows)
    @test free_correlation_operational_progress.denominator_kind ===
        :conjunctive_pre_scientific_operational_gates
    @test !free_correlation_operational_progress.
        counts_toward_scientific_denominator
    @test free_correlation_operational_progress.source_artifact ===
        :mgmfrm_free_latent_correlation_2d_resource_probe_receipt
    @test Tuple(row.gate_status
        for row in free_correlation_operational_progress.gate_rows) ==
        (:failed, :pending, :pending)

    free_correlation_plan = BayesianMGMFRM.
        _mgmfrm_free_latent_correlation_2d_study_plan()
    @test free_correlation_operational_progress.denominator == 1 +
        Int(free_correlation_plan.resource_policy.initial_gradient_probe.
            short_nuts_profile_required) +
        Int(free_correlation_plan.resource_policy.initial_gradient_probe.
            atomic_runner_required)
    free_correlation_scientific_progress = only(row
        for row in progress_evidence_rows
        if row.scope === :free_latent_correlation_scientific_execution)
    @test free_correlation_scientific_progress.gate_status ===
        :blocked_by_operational_prerequisites
    @test free_correlation_scientific_progress.execution_status ===
        :not_executed
    @test free_correlation_scientific_progress.numerator == 0
    @test free_correlation_scientific_progress.denominator == 525
    @test free_correlation_scientific_progress.attainment_percent == 0.0
    @test free_correlation_scientific_progress.denominator ==
        length(free_correlation_plan.units)
    @test free_correlation_scientific_progress.denominator ==
        free_correlation_plan.phases.feasibility.n_units +
        free_correlation_plan.denominator_policy.n_planned_evaluation_units
    @test free_correlation_scientific_progress.component_counts.
        computation_only_feasibility == (numerator = 0, denominator = 25)
    @test free_correlation_scientific_progress.component_counts.
        recovery_evaluation == (numerator = 0, denominator = 500)
    @test free_correlation_scientific_progress.
        counts_toward_scientific_denominator
    @test free_correlation_scientific_progress.source_artifact ===
        :mgmfrm_free_latent_correlation_2d_study_plan_v2
    @test free_correlation_scientific_progress.source_contract ==
        free_correlation_plan.plan_id
    @test free_correlation_scientific_progress.source_artifact_sha256 ==
        free_correlation_plan.plan_fingerprint

    ld1b_integration_progress = only(row
        for row in progress_evidence_rows
        if row.scope === :v0_1_2_ld1b_integration)
    @test ld1b_integration_progress.record_status ===
        :current_dirty_worktree_snapshot_recorded
    @test ld1b_integration_progress.gate_status ===
        :partially_attained_local_worktree_only
    @test ld1b_integration_progress.execution_status ===
        :bounded_verification_mcmc_nonpilot_integration_evidence_only
    @test ld1b_integration_progress.numerator == 7
    @test ld1b_integration_progress.denominator == 9
    @test ld1b_integration_progress.attainment_percent == 77.8
    @test ld1b_integration_progress.denominator ==
        length(ld1b_integration_progress.gate_rows)
    @test ld1b_integration_progress.gate_rows == BayesianMGMFRM.
        _release_scope_current_ld1b_integration_gate_rows()
    @test count(row -> row.gate_status in
            (:complete, :complete_local_worktree),
        ld1b_integration_progress.gate_rows) == 7
    @test count(row -> row.gate_status === :complete_local_worktree,
        ld1b_integration_progress.gate_rows) == 5
    @test only(row for row in ld1b_integration_progress.gate_rows
        if row.gate === :canonical_single_job_worker) == (
            gate = :canonical_single_job_worker,
            gate_status = :complete_local_worktree,
            evidence_scope = :local_dirty_worktree,
        )
    @test only(row for row in ld1b_integration_progress.gate_rows
        if row.gate ===
            :final_worker_source_pinning_and_identity_regeneration) == (
            gate = :final_worker_source_pinning_and_identity_regeneration,
            gate_status = :complete_local_worktree,
            evidence_scope = :local_dirty_worktree,
        )
    @test only(row for row in ld1b_integration_progress.gate_rows
        if row.gate === :bounded_canonical_smoke_on_pinned_source) == (
            gate = :bounded_canonical_smoke_on_pinned_source,
            gate_status = :complete_local_worktree,
            evidence_scope = :local_dirty_worktree,
        )
    @test !ld1b_integration_progress.counts_toward_scientific_denominator
    @test !ld1b_integration_progress.release_lineage_verified
    @test ld1b_integration_progress.scientific_numerator_contribution == 0
    @test ld1b_integration_progress.source_artifact ===
        :roadmap_current_v0_1_2_ld1b_integration_checklist

    ld1b_contract = local_dependence_calibration_pilot_contract()
    ld1b_scientific_progress = only(row
        for row in progress_evidence_rows
        if row.scope === :ld1b_scientific_execution)
    @test ld1b_scientific_progress.gate_status ===
        :blocked_by_open_integration_gates
    @test ld1b_scientific_progress.execution_status === :not_executed
    @test ld1b_scientific_progress.numerator == 0
    @test ld1b_scientific_progress.denominator == 660
    @test ld1b_scientific_progress.attainment_percent == 0.0
    @test ld1b_scientific_progress.denominator ==
        ld1b_contract.planning.n_jobs
    @test ld1b_scientific_progress.component_counts.eligible_fitting_jobs ==
        (numerator = 0, denominator = ld1b_contract.planning.n_fit_jobs)
    @test ld1b_scientific_progress.component_counts.
        planned_structural_rejections ==
            (numerator = 0,
                denominator = ld1b_contract.planning.n_pre_fit_rejection_jobs)
    @test ld1b_scientific_progress.counts_toward_scientific_denominator
    @test ld1b_scientific_progress.source_artifact ===
        :local_dependence_calibration_pilot_contract_v1
    @test ld1b_scientific_progress.source_contract_schema ==
        ld1b_contract.schema
    @test any(row -> row.family === :gmfrm &&
        row.evidence === :guarded_fit_method_wiring,
        release_scope_with_evidence.evidence_rows)
    @test any(row -> row.family === :mgmfrm &&
        row.evidence === :guarded_fit_public_exposure_review,
        release_scope_with_evidence.evidence_rows)
    @test any(row -> row.family === :gmfrm &&
        row.evidence === :guarded_generalized_fit_cache,
        release_scope_with_evidence.evidence_rows)
    @test any(row -> row.family === :mgmfrm &&
        row.evidence === :guarded_generalized_fit_cache,
        release_scope_with_evidence.evidence_rows)
    @test any(row -> row.family === :all_fit_objects &&
        row.evidence === :fit_reproduction_cache_identity_check,
        release_scope_with_evidence.evidence_rows)
    @test any(row -> row.family === :all_package_surfaces &&
        row.evidence === :pre_registration_gate_available &&
        row.artifact === :scripts_pre_registration_gate,
        release_scope_with_evidence.evidence_rows)
    @test any(row -> row.family === :all_package_surfaces &&
        row.evidence === :documenter_html_page_size_gate &&
        row.artifact === :docs_make,
        release_scope_with_evidence.evidence_rows)
    @test any(row -> row.family === :gmfrm_mgmfrm &&
        row.scope === :v0_1_1_generalized_refinement &&
        row.evidence === :implementation_checklist_created &&
        row.status === :done &&
        row.phase_status === :completed &&
        row.historical_release,
        release_scope_with_evidence.evidence_rows)
    @test any(row -> row.family === :all_evidence_artifacts &&
        row.scope === :evidence_schema_policy &&
        row.evidence === :evidence_artifact_schema_policy &&
        row.status === :done,
        release_scope_with_evidence.evidence_rows)
    @test any(row -> row.family === :all_package_surfaces &&
        row.scope === :status_synchronization &&
        row.evidence === :release_gate_check &&
        row.status === :done,
        release_scope_with_evidence.evidence_rows)
    @test any(row -> row.family === :all_related_software &&
        row.scope === :positioning_and_non_superiority &&
        row.evidence === :related_software_capability_matrix &&
        row.status === :done,
        release_scope_with_evidence.evidence_rows)
    release_gate = release_gate_check()
    @test release_gate.schema == "bayesianmgmfrm.release_gate_check.v1"
    @test release_gate.object === :release_gate_check
    @test release_gate.status === :passed
    @test release_gate.summary.passed
    @test release_gate.summary.n_failed_rows == 0
    @test !release_gate.summary.broad_generalized_fit_allowed
    @test !release_gate.summary.model_weight_claims_allowed
    @test release_gate.summary.development_version ==
        string(pkgversion(BayesianMGMFRM))
    @test release_gate.summary.development_phase ===
        :v0_1_2_fixed_q_productionization
    @test release_gate.summary.development_next_gate ===
        :v0_1_2_fixed_q_productionization
    @test release_gate.summary.next_gate ===
        :manual_publication_or_registration_by_user_only
    @test any(row -> row.source === :documentation &&
        row.target === :readme_public_surface &&
        row.check === :document_present &&
        row.status === :passed,
        release_gate.rows)
    @test any(row -> row.source === :documentation &&
        row.target === :docs_scope_public_surface &&
        row.check === :document_present &&
        row.status === :passed,
        release_gate.rows)
    @test all(row -> row.source !== :documentation ||
        row.check === :document_present,
        release_gate.rows)
    document_specs = BayesianMGMFRM._release_gate_document_specs()
    @test !any(spec -> spec.path == "ROADMAP.md" ||
        spec.path == joinpath("docs", "src", "mgmfrm-research-roadmap.md"),
        document_specs)
    @test any(row -> row.source === :manifest &&
        row.target === :post_v0_2_external_validation_blocked &&
        row.status === :passed,
        release_gate.rows)
    @test any(row -> row.source === :manifest &&
        row.target === :related_software_capability_matrix_evidence_row &&
        row.status === :passed,
        release_gate.rows)
    @test all(target -> any(row -> row.source === :manifest &&
            row.target === target && row.status === :passed,
            release_gate.rows),
        (:roadmap_progress_evidence_row_set,
            :roadmap_progress_evidence_schema,
            :free_correlation_operational_progress,
            :free_correlation_scientific_progress,
            :v0_1_2_ld1b_integration_progress,
            :ld1b_scientific_progress))
    missing_doc_root = mktempdir()
    missing_doc_gate = release_gate_check(; root = missing_doc_root)
    @test missing_doc_gate.status === :failed
    @test !missing_doc_gate.summary.passed
    @test missing_doc_gate.summary.n_failed_rows > 0
    @test any(row -> row.check === :document_present &&
        row.status === :failed,
        missing_doc_gate.rows)
    @test_throws ArgumentError release_gate_check(;
        root = missing_doc_root,
        throw_on_failure = true)
    copy_release_gate_documents = function(destination)
        package_root = normpath(joinpath(dirname(@__DIR__), ".."))
        for document_spec in document_specs
            source = joinpath(package_root, document_spec.path)
            target = joinpath(destination, document_spec.path)
            mkpath(dirname(target))
            cp(source, target)
        end
    end
    mktempdir() do prose_root
        copy_release_gate_documents(prose_root)
        readme_path = joinpath(prose_root, "README.md")
        write(readme_path,
            read(readme_path, String) *
            "\nReader-facing wording may evolve without changing support status.\n")
        prose_edit_gate = release_gate_check(; root = prose_root)
        @test prose_edit_gate.status === :passed
        @test prose_edit_gate.summary.passed
    end
    structured_surfaces = Tuple(
        row.surface === :scalar_gmfrm_guarded_experimental ?
            merge(row, (; experimental_public = false)) : row
        for row in release_scope_with_evidence.public_fit_surfaces
    )
    structured_drift_scope = merge(
        release_scope_with_evidence,
        (; public_fit_surfaces = structured_surfaces),
    )
    structured_drift_rows = BayesianMGMFRM._release_gate_manifest_rows(
        structured_drift_scope)
    @test any(row -> row.target === :scalar_gmfrm_experimental_public &&
        row.check === :manifest_consistency &&
        row.status === :failed,
        structured_drift_rows)
    case_provenance = case_study_provenance_manifest()
    @test case_provenance.schema ==
        "bayesianmgmfrm.case_study_provenance_manifest.v1"
    @test case_provenance.object === :case_study_provenance_manifest
    @test case_provenance.status === :synchronized
    @test case_provenance.summary.passed
    @test case_provenance.summary.n_source_records == 2
    @test case_provenance.summary.n_archive_records == 4
    @test case_provenance.summary.n_publication_facing_archives == 2
    @test case_provenance.summary.all_source_records_anonymized
    @test case_provenance.summary.all_license_records_declared
    @test case_provenance.summary.publication_archives_synchronized
    @test case_provenance.summary.no_public_source_release
    @test case_provenance.summary.no_publication_actions
    @test !case_provenance.summary.license_grant
    @test !case_provenance.summary.irb_determination
    @test !case_provenance.summary.publication_or_registration_action
    @test !case_provenance.summary.manuscript_claims_allowed
    @test any(row -> row.archive === :full_paper_reproduction_archive &&
        row.publication_facing &&
        row.provenance_sync_passed,
        case_provenance.archive_records)
    @test_throws ArgumentError case_study_provenance_manifest(
        source_records = NamedTuple[])
    incomplete_provenance = case_study_provenance_manifest(
        source_records = (;
            source_id = :local_case,
            license_status = :missing,
            anonymization_status = :pseudonymized,
            direct_identifiers_removed = true,
        ))
    @test incomplete_provenance.status === :incomplete
    @test !incomplete_provenance.summary.all_license_records_declared
    @test spec.family === :mfrm
    @test spec.dimensions == 1
    @test spec.discrimination === :none
    @test spec.estimation_status === :fit_supported
    @test spec.q_matrix === nothing
    equation = model_equation(spec)
    @test equation.schema == "bayesianmgmfrm.model_equation.v1"
    @test equation.family === :mfrm
    @test equation.probability_form === :adjacent_category_softmax
    @test equation.fit_ready
    @test isempty(equation.implementation_gaps)
    @test :threshold_steps in equation.required_blocks
    spec_constraints = constraint_table(spec)
    @test any(row -> row.block === :person && row.status === :implemented, spec_constraints)
    @test any(row -> row.block === :thresholds && row.constraint === :sum_to_zero, spec_constraints)
    spec_audit = model_surface_audit(spec)
    @test length(spec_audit) >= length(spec_constraints)
    @test all(row -> row.schema == "bayesianmgmfrm.model_surface_audit_row.v1",
        spec_audit)
    @test all(row -> row.current_status === :supported, spec_audit)
    @test any(row -> row.block === :person &&
        row.source_symbol == "theta_p" &&
        row.raw_coordinate === :person &&
        row.constraint === :free &&
        row.prior_scale === :person_sd &&
        row.report_label === :person_measure,
        spec_audit)
    @test any(row -> row.block === :thresholds &&
        row.source_symbol == "d_m or d_im" &&
        row.constraint === :sum_to_zero &&
        row.prior_scale === :step_sd &&
        row.report_label === :category_threshold,
        spec_audit)
    spec_identification = identification_declarations(spec)
    @test any(row -> row.block === :rater && row.rule === :reference &&
        row.components == (:reference,), spec_identification)
    @test any(row -> row.block === :thresholds && row.rule === :sum_to_zero &&
        row.components == (:sum_to_zero,), spec_identification)
    design_constraints = constraint_table(design)
    @test any(row -> row.block === :person && row.n_parameters == 1 &&
        row.parameter_names == ["person[E1]"], design_constraints)
    design_identification = identification_declarations(design)
    @test any(row -> row.block === :person && row.rule === :free &&
        row.n_parameters == 1 &&
        row.parameter_names == ["person[E1]"], design_identification)
    @test any(row -> row.block === :rater && row.rule === :reference &&
        row.n_parameters == 0 &&
        isempty(row.parameter_names), design_identification)
    binary_layout = fit_ready_parameter_layout(spec)
    @test binary_layout.schema == "bayesianmgmfrm.fit_ready_parameter_layout.v1"
    @test binary_layout.family === :mfrm
    @test binary_layout.fit_ready
    @test binary_layout.public_fit
    @test binary_layout.parameterization === :direct
    @test binary_layout.parameter_names == design.parameter_names
    @test binary_layout.raw_parameter_names == design.parameter_names
    @test binary_layout.constrained_parameter_names == design.parameter_names
    @test any(row -> row.raw_block === :person &&
        row.constrained_block === :person &&
        row.transform === :identity &&
        row.raw_parameter_names == ["person[E1]"],
        binary_layout.transforms)
    binary_domain = domain_compilation_summary(spec)
    @test any(row -> row.domain_option === :family &&
        row.compiled_role === :likelihood_kernel &&
        row.fit_ready &&
        row.public_fit,
        binary_domain)
    binary_scoring = only(filter(row -> row.compiled_role === :scoring_vector,
        binary_domain))
    @test binary_scoring.domain_option === :thresholds
    @test binary_scoring.block === :thresholds
    @test binary_scoring.scoring_vector == data.category_levels
    @test binary_scoring.constraint === :sum_to_zero
    @test binary_scoring.prior === :normal
    @test any(row -> row.block === :person &&
        row.compiled_role === :additive_block &&
        row.parameter_names == ["person[E1]"],
        binary_domain)

    data_manifest = model_manifest(data)
    @test data_manifest.schema == "bayesianmgmfrm.model_manifest.v1"
    @test data_manifest.object === :data
    @test data_manifest.data.n_observations == data.n
    @test data_manifest.data.columns.person === :examinee
    @test data_manifest.data.levels.category == data.category_levels
    @test data_manifest.rating_design.schema ==
        "bayesianmgmfrm.rating_design_audit.v1"
    @test data_manifest.rating_design.object === :rating_design_audit
    @test data_manifest.rating_design.summary.nonignorable_assignment_flagged

    @test design.parameter_names == ["person[E1]"]
    @test design.blocks[:person] == 1:1
    @test isempty(design.blocks[:rater])
    @test isempty(design.blocks[:item])
    @test isempty(design.blocks[:thresholds])
    @test design.identification[:person] === :free
    @test design.identification[:rater] === :reference_first
    @test design.identification[:item] === :reference_first
    @test design.identification[:thresholds] === :sum_to_zero

    params = [0.4]
    pointwise = pointwise_loglikelihood(design, params)
    binary_predictor_values = linear_predictor_values(design, params)
    location = 0.4
    eta0 = 0.0
    eta1 = location
    denom = log(exp(eta0) + exp(eta1))
    @test pointwise[1] ≈ eta0 - denom
    @test pointwise[2] ≈ eta1 - denom
    @test length(binary_predictor_values) == data.n * length(data.category_levels)
    @test binary_predictor_values[1].eta ≈ eta0
    @test binary_predictor_values[1].location_value ≈ location
    @test isempty(binary_predictor_values[1].step_values)
    @test binary_predictor_values[2].eta ≈ eta1
    @test binary_predictor_values[2].step_values == [0.0]
    @test binary_predictor_values[2].log_denominator ≈ denom
    @test binary_predictor_values[2].log_probability ≈ eta1 - denom

    summary = coverage_summary(spec)
    @test summary.n_ratings == 2
    @test summary.n_persons == 1
    @test summary.n_raters == 1
    @test summary.n_items == 1
    @test summary.validation.passed
    @test [row.category for row in summary.category_counts] == [0, 1]
    @test sum(row.count for row in summary.category_counts) == 2
    @test any(row -> row.facet === :person && row.n_levels == 1, summary.facet_summary)

    matrix = coverage_matrix(spec)
    @test matrix.row_facet === :rater
    @test matrix.column_facet === :person
    @test matrix.row_levels == Any["R1"]
    @test matrix.column_levels == Any["E1"]
    @test matrix.counts == reshape([2], 1, 1)

    binary_thresholds = threshold_map_data(design; params)
    @test length(binary_thresholds) == 1
    @test binary_thresholds[1].status === :fixed_zero
    @test binary_thresholds[1].value == 0.0
    binary_rows = design_row_table(design)
    @test length(binary_rows) == 2
    @test binary_rows[1].person_parameter_indices == [1]
    @test binary_rows[1].rater_parameter_index === missing
    @test isempty(binary_rows[1].threshold_path)
    @test isequal(binary_rows[2].threshold_parameter_indices, [missing])
    @test binary_rows[2].threshold_statuses == [:fixed_zero]

    identified = (
        examinee = ["E1", "E1", "E1", "E2", "E2", "E2"],
        rater = ["R1", "R2", "R1", "R1", "R2", "R1"],
        item = ["I1", "I1", "I2", "I1", "I2", "I2"],
        task = ["T1", "T1", "T2", "T1", "T2", "T2"],
        score = [0, 1, 2, 1, 0, 2],
    )
    identified_data = FacetData(identified; person = :examinee, rater = :rater, item = :item, score = :score, task = :task)
    identified_spec = mfrm_spec(identified_data; thresholds = :partial_credit)
    identified_design = getdesign(identified_spec)
    spec_manifest = model_manifest(identified_spec)
    @test spec_manifest.object === :spec
    @test spec_manifest.status_policy == spec_manifest.spec.status_policy
    @test spec_manifest.spec.model_surface_audit == model_surface_audit(identified_spec)
    @test spec_manifest.spec.family === :mfrm
    @test spec_manifest.spec.scope === :minimal_mfrm_rsm_pcm
    @test spec_manifest.spec.thresholds === :partial_credit
    @test spec_manifest.spec.dimensions == 1
    @test spec_manifest.spec.discrimination === :none
    @test spec_manifest.spec.estimation_status === :fit_supported
    @test spec_manifest.spec.status_policy.schema == "bayesianmgmfrm.status_policy.v1"
    @test spec_manifest.spec.status_policy.status_label === :supported
    @test spec_manifest.spec.status_policy.public_fit
    @test !spec_manifest.spec.status_policy.experimental_public
    @test :model_weight_or_superiority in spec_manifest.spec.status_policy.blocked_claims
    @test spec_manifest.spec.equation.fit_ready
    @test spec_manifest.spec.equation.kernel == model_equation(identified_spec).kernel
    @test any(row -> row.block === :thresholds && row.constraint === :sum_to_zero,
        spec_manifest.spec.constraints)
    @test any(row -> row.block === :item && row.rule === :reference,
        spec_manifest.spec.identification_declarations)
    @test spec_manifest.validation.passed
    @test spec_manifest.data.optional_facets == [:task]
    @test spec_manifest.data.levels.optional.task == identified_data.optional_levels[:task]
    @test isequal(spec_manifest.rating_design, rating_design_audit(identified_spec))
    @test spec_manifest.rating_design.family === :mfrm
    @test spec_manifest.rating_design.summary.rating_graph_status === :connected
    design_manifest = model_manifest(identified_design)
    @test design_manifest.object === :design
    @test design_manifest.status_policy == design_manifest.spec.status_policy
    @test design_manifest.model_surface_audit == model_surface_audit(identified_design)
    @test isequal(design_manifest.rating_design, spec_manifest.rating_design)
    @test design_manifest.design.n_parameters == length(identified_design.parameter_names)
    @test design_manifest.design.parameter_names == identified_design.parameter_names
    @test any(row -> row.block === :thresholds && row.identification === :sum_to_zero,
        design_manifest.design.blocks)
    @test any(row -> row.block === :rater && row.n_parameters == 1,
        design_manifest.design.constraints)
    @test any(row -> row.block === :thresholds &&
        :sum_to_zero in row.components &&
        row.n_parameters == 2,
        design_manifest.design.identification_declarations)
    @test design_manifest.design.identification.rater === :reference_first
    @test design_manifest.design.raw_parameterization === nothing
    @test identified_design.parameter_names == [
        "person[E1]",
        "person[E2]",
        "rater[R2]",
        "item[I2]",
        "step[item=I1,1]",
        "step[item=I2,1]",
    ]
    identified_layout = fit_ready_parameter_layout(identified_design)
    @test identified_layout.n_parameters == length(identified_design.parameter_names)
    @test [row.block for row in identified_layout.blocks] ==
        sort([row.block for row in identified_layout.blocks]; by = string)
    @test any(row -> row.block === :thresholds &&
        row.parameter_names == ["step[item=I1,1]", "step[item=I2,1]"],
        identified_layout.blocks)
    @test any(row -> row.raw_block === :thresholds &&
        row.constrained_block === :thresholds &&
        row.constraint === :sum_to_zero,
        identified_layout.transforms)
    identified_domain = domain_compilation_summary(identified_spec)
    identified_design_domain = domain_compilation_summary(identified_design)
    @test length(identified_domain) == length(identified_design_domain)
    @test [row.compiled_role for row in identified_domain] ==
        [row.compiled_role for row in identified_design_domain]
    @test isequal(
        [row.block for row in identified_domain],
        [row.block for row in identified_design_domain],
    )
    identified_threshold_domain = only(filter(row ->
        row.compiled_role === :scoring_vector,
        identified_domain))
    @test identified_threshold_domain.block === :thresholds
    @test identified_threshold_domain.parameter_names ==
        ["step[item=I1,1]", "step[item=I2,1]"]
    @test identified_threshold_domain.scoring_vector == identified_data.category_levels
    @test identified_threshold_domain.validation_requirement === :ordinal_score_categories
    identified_item_domain = only(filter(row -> row.block === :item &&
        row.compiled_role === :additive_block,
        identified_domain))
    @test identified_item_domain.constraint === :reference_first
    @test identified_item_domain.prior_block === :item
    @test identified_item_domain.prior === :normal
    identified_validation_domain = only(filter(row ->
        row.domain_option === :validation &&
        row.compiled_role === :validation_requirement,
        identified_domain))
    @test identified_validation_domain.status === :passed
    @test identified_validation_domain.option_value.passed

    identified_params = [0.4, -0.1, 0.2, -0.3, 0.5, -0.25]
    identified_pointwise = pointwise_loglikelihood(identified_design, identified_params)
    row2_location = 0.4 - 0.2 - 0.0
    row2_etas = [0.0, row2_location - 0.5, 2row2_location]
    @test identified_pointwise[2] ≈ row2_etas[2] - (maximum(row2_etas) + log(sum(exp.(row2_etas .- maximum(row2_etas)))))
    row3_location = 0.4 - 0.0 - (-0.3)
    row3_etas = [0.0, row3_location - (-0.25), 2row3_location]
    @test identified_pointwise[3] ≈ row3_etas[3] - (maximum(row3_etas) + log(sum(exp.(row3_etas .- maximum(row3_etas)))))

    raw_person = [0.4, -0.1]
    raw_rater = [0.0, 0.2]
    raw_item = [0.0, -0.3]
    raw_steps = [[0.5, -0.5], [-0.25, 0.25]]
    @test identified_pointwise ≈ raw_pcm_pointwise(identified_data, raw_person, raw_rater, raw_item, raw_steps)

    rater_person = coverage_matrix(identified_spec; rows = :rater, columns = :person)
    @test rater_person.row_levels == Any["R1", "R2"]
    @test rater_person.column_levels == Any["E1", "E2"]
    @test rater_person.counts == [2 2; 1 1]
    task_rater = coverage_matrix(identified_data; rows = :task, columns = :rater)
    @test task_rater.row_levels == Any["T1", "T2"]
    @test task_rater.column_levels == Any["R1", "R2"]
    @test task_rater.counts == [2 1; 2 1]
    @test_throws ArgumentError coverage_matrix(data; rows = :task, columns = :rater)

    overlap = rater_overlap(identified_data)
    @test length(overlap) == 1
    @test overlap[1].rater_a == "R1"
    @test overlap[1].rater_b == "R2"
    @test overlap[1].shared_units == 2
    @test overlap[1].jaccard ≈ 2 / 4

    task_overlap = rater_overlap(identified_spec; unit = :person_task)
    @test only(task_overlap).shared_units == 2
    @test_throws ArgumentError rater_overlap(data; unit = :person_task)

    design_audit = rating_design_audit(identified_spec; min_shared_units = 2)
    @test design_audit.schema == "bayesianmgmfrm.rating_design_audit.v1"
    @test design_audit.object === :rating_design_audit
    @test design_audit.passed
    @test design_audit.family === :mfrm
    @test design_audit.estimation_status === :fit_supported
    @test design_audit.summary.n_rating_graph_components == 1
    @test design_audit.summary.rater_linking_status === :connected
    @test design_audit.summary.anchor_status === :not_declared
    @test !design_audit.summary.structural_missingness_distinguishable
    @test design_audit.summary.nonignorable_assignment_flagged
    @test any(row -> row.audit === :observed_cell_coverage &&
        row.facets == (:person, :rater, :item) &&
        row.n_expected == 8 &&
        row.n_observed == 6 &&
        row.n_missing == 2 &&
        row.note ===
            :structural_vs_accidental_missingness_not_identified_by_observed_long_data,
        design_audit.rows)
    @test any(row -> row.audit === :sparse_person_rater_item_blocks &&
        row.status === :sparse_observed_cells_detected &&
        row.n_sparse == 6,
        design_audit.rows)
    @test any(row -> row.audit === :repeated_person_rater_item_ratings &&
        row.status === :none_detected &&
        row.n_repeated == 0,
        design_audit.rows)
    @test any(row -> row.audit === :optional_time_order_fields &&
        row.status === :not_declared &&
        row.details.optional_facets == (:task,),
        design_audit.rows)
    @test any(row -> row.audit === :nonignorable_assignment &&
        row.status === :limitation &&
        row.severity === :warning,
        design_audit.rows)
    weak_design_audit = rating_design_audit(identified_spec; min_shared_units = 3)
    @test !weak_design_audit.passed
    @test weak_design_audit.summary.rater_linking_status === :disconnected
    @test any(row -> row.audit === :rater_linking &&
        row.status === :disconnected &&
        row.n_sparse == 1,
        weak_design_audit.rows)
    repeated = (;
        examinee = vcat(identified.examinee, ["E1"]),
        rater = vcat(identified.rater, ["R1"]),
        item = vcat(identified.item, ["I1"]),
        task = vcat(identified.task, ["T1"]),
        score = vcat(identified.score, [1]),
    )
    repeated_data = FacetData(repeated;
        person = :examinee,
        rater = :rater,
        item = :item,
        score = :score,
        task = :task)
    repeated_audit = rating_design_audit(repeated_data)
    @test repeated_audit.summary.n_repeated_person_rater_item_cells == 1
    @test any(row -> row.audit === :repeated_person_rater_item_ratings &&
        row.status === :repeated_ratings_detected &&
        row.n_repeated == 1,
        repeated_audit.rows)
    ordered = (; identified..., occasion = [1, 2, 3, 4, 5, 6])
    ordered_data = FacetData(ordered;
        person = :examinee,
        rater = :rater,
        item = :item,
        score = :score,
        task = :task,
        occasion = :occasion)
    ordered_audit = rating_design_audit(ordered_data)
    @test any(row -> row.audit === :optional_time_order_fields &&
        row.status === :recorded_not_modeled &&
        row.details.time_order_facets == (:occasion,),
        ordered_audit.rows)
    @test_throws ArgumentError rating_design_audit(identified_spec;
        min_shared_units = 0)
    @test_throws ArgumentError rating_design_audit(identified_spec;
        min_sparse_cell_count = 0)

    pcm_thresholds = threshold_map_data(identified_design; params = identified_params)
    @test length(pcm_thresholds) == 4
    @test pcm_thresholds[1].parameter_name == "step[item=I1,1]"
    @test pcm_thresholds[1].value == 0.5
    @test pcm_thresholds[2].status === :sum_to_zero_derived
    @test pcm_thresholds[2].value == -0.5
    @test pcm_thresholds[4].value == 0.25
    identified_rows = design_row_table(identified_spec)
    @test length(identified_rows) == identified_data.n
    @test identified_rows[2].person_parameter_indices == [1]
    @test identified_rows[2].rater_parameter_index == 3
    @test identified_rows[2].rater_parameter_name == "rater[R2]"
    @test identified_rows[2].item_parameter_index === missing
    @test identified_rows[2].threshold_parameter_indices == [5]
    @test identified_rows[2].threshold_parameter_names == ["step[item=I1,1]"]
    @test identified_rows[3].item_parameter_index == 4
    @test isequal(identified_rows[3].threshold_parameter_indices, [6, missing])
    @test identified_rows[3].threshold_statuses == [:free, :sum_to_zero_derived]
    @test isempty(identified_rows[3].loading_parameter_indices)
    @test isempty(identified_rows[3].discrimination_parameter_indices)
    identified_predictors = linear_predictor_table(identified_spec)
    identified_predictor_values = linear_predictor_values(identified_spec, identified_params)
    @test length(identified_predictors) == identified_data.n * length(identified_data.category_levels)
    @test length(identified_predictor_values) == length(identified_predictors)
    @test identified_predictors[1].kernel === :mfrm_additive
    @test identified_predictors[1].row == 1
    @test identified_predictors[1].category == 0
    @test identified_predictors[1].location_multiplier == 0
    @test isempty(identified_predictors[1].step_parameter_indices)
    @test identified_predictors[2].category == 1
    @test identified_predictors[2].location_multiplier == 1
    @test identified_predictors[2].step_parameter_names == ["step[item=I1,1]"]
    @test identified_predictors[3].category == 2
    @test identified_predictors[3].location_multiplier == 2
    @test isequal(identified_predictors[3].step_parameter_indices, [5, missing])
    @test identified_predictors[3].step_blocks == [:thresholds, :thresholds]
    @test only(filter(row -> row.row == 3 && row.category == 2, identified_predictors)).observed
    row2_cat1_value = only(filter(row -> row.row == 2 && row.category == 1, identified_predictor_values))
    @test row2_cat1_value.person_value ≈ 0.4
    @test row2_cat1_value.rater_value ≈ 0.2
    @test row2_cat1_value.item_value ≈ 0.0
    @test row2_cat1_value.location_value ≈ row2_location
    @test row2_cat1_value.step_values == [0.5]
    @test row2_cat1_value.step_sum ≈ 0.5
    @test row2_cat1_value.eta ≈ row2_etas[2]
    @test row2_cat1_value.log_probability ≈ identified_pointwise[2]
    row3_cat2_value = only(filter(row -> row.row == 3 && row.category == 2, identified_predictor_values))
    @test row3_cat2_value.location_value ≈ row3_location
    @test row3_cat2_value.step_values ≈ [-0.25, 0.25]
    @test row3_cat2_value.step_sum ≈ 0.0
    @test row3_cat2_value.eta ≈ row3_etas[3]
    @test row3_cat2_value.log_probability ≈ identified_pointwise[3]
    @test [row.log_probability for row in filter(row -> row.observed, identified_predictor_values)] ≈
        identified_pointwise

    shifted_person_rater = raw_pcm_pointwise(
        identified_data,
        raw_person .+ 1.3,
        raw_rater .+ 1.3,
        raw_item,
        raw_steps,
    )
    shifted_person_item = raw_pcm_pointwise(
        identified_data,
        raw_person .- 0.7,
        raw_rater,
        raw_item .- 0.7,
        raw_steps,
    )
    shifted_item_steps = raw_pcm_pointwise(
        identified_data,
        raw_person,
        raw_rater,
        [raw_item[1], raw_item[2] + 0.9],
        [raw_steps[1], raw_steps[2] .- 0.9],
    )
    @test identified_pointwise ≈ shifted_person_rater
    @test identified_pointwise ≈ shifted_person_item
    @test identified_pointwise ≈ shifted_item_steps

    rsm_spec = mfrm_spec(identified_data; thresholds = :rating_scale)
    rsm_design = getdesign(rsm_spec)
    @test rsm_design.parameter_names[end] == "step[1]"
    @test count(name -> startswith(name, "step"), rsm_design.parameter_names) == 1
    rsm_params = [0.4, -0.1, 0.2, -0.3, 0.5]
    rsm_pointwise = pointwise_loglikelihood(rsm_design, rsm_params)
    rsm_predictor_values = linear_predictor_values(rsm_design, rsm_params)
    rsm_row3_location = 0.4 - 0.0 - (-0.3)
    rsm_row3_etas = [0.0, rsm_row3_location - 0.5, 2rsm_row3_location]
    @test rsm_pointwise[3] ≈ rsm_row3_etas[3] - test_logsumexp(rsm_row3_etas)
    rsm_row3_cat2 = only(filter(row -> row.row == 3 && row.category == 2, rsm_predictor_values))
    @test rsm_row3_cat2.step_values ≈ [0.5, -0.5]
    @test rsm_row3_cat2.eta ≈ rsm_row3_etas[3]
    @test rsm_row3_cat2.log_probability ≈ rsm_pointwise[3]

    rsm_thresholds = threshold_map_data(rsm_design; params = rsm_params)
    @test length(rsm_thresholds) == 2
    @test rsm_thresholds[1].item === missing
    @test rsm_thresholds[1].value == 0.5
    @test rsm_thresholds[2].status === :sum_to_zero_derived
    @test rsm_thresholds[2].value == -0.5

    anchored_spec = mfrm_spec(identified_data;
        thresholds = :partial_credit,
        anchors = [
            (block = :item, value = 0.0, type = :hard),
            (block = :rater, value = 0.0, type = :soft, scale = 0.25),
        ])
    @test anchored_spec.estimation_status === :specified_only
    anchored_identification = identification_declarations(anchored_spec)
    hard_anchor = only(filter(row -> row.rule === :hard_anchor, anchored_identification))
    @test hard_anchor.block === :item
    @test hard_anchor.components == (:hard_anchor, :fixed)
    @test hard_anchor.anchor_type === :hard_anchor
    @test hard_anchor.anchor_value == 0.0
    @test ismissing(hard_anchor.anchor_scale)
    soft_anchor = only(filter(row -> row.rule === :soft_anchor, anchored_identification))
    @test soft_anchor.block === :rater
    @test soft_anchor.anchor_type === :soft_anchor
    @test soft_anchor.anchor_value == 0.0
    @test soft_anchor.anchor_scale == 0.25
    @test any(row -> row.constraint === :hard_anchor, constraint_table(anchored_spec))
    @test any(row -> row.constraint === :soft_anchor, constraint_table(anchored_spec))
    @test_throws ArgumentError domain_compilation_summary(anchored_spec)
    anchored_domain = domain_compilation_summary(anchored_spec; preview = true)
    hard_anchor_domain = only(filter(row ->
        row.domain_option === :anchors &&
        row.constraint === :hard_anchor,
        anchored_domain))
    @test hard_anchor_domain.block === :item
    @test hard_anchor_domain.compiled_role === :constraint
    @test hard_anchor_domain.compiler_stage === :specified_only_preview
    @test !hard_anchor_domain.fit_ready
    soft_anchor_domain = only(filter(row ->
        row.domain_option === :anchors &&
        row.constraint === :soft_anchor,
        anchored_domain))
    @test soft_anchor_domain.block === :rater
    @test soft_anchor_domain.transform === :soft_anchor_prior
    @test soft_anchor_domain.validation_requirement === :anchor_declared
    anchor_linking = anchor_linking_summary(anchored_spec; min_shared_units = 2)
    @test anchor_linking.schema == "bayesianmgmfrm.anchor_linking_summary.v1"
    @test anchor_linking.passed
    @test anchor_linking.family === :mfrm
    @test anchor_linking.estimation_status === :specified_only
    @test anchor_linking.anchor_status === :declared
    @test anchor_linking.n_anchors == 2
    @test anchor_linking.n_hard_anchors == 1
    @test anchor_linking.n_soft_anchors == 1
    @test anchor_linking.n_anchor_target_failures == 0
    @test all(row -> row.passed, anchor_linking.anchor_rows)
    @test anchor_linking.rater_linking_status === :connected
    @test anchor_linking.n_rater_components == 1
    @test anchor_linking.rater_components == (("R1", "R2"),)
    @test anchor_linking.largest_rater_component == 2
    @test anchor_linking.n_links_at_or_above_min == 1
    @test anchor_linking.minimum_shared_units == 2
    @test anchor_linking.anchor_sensitivity_status === :not_supplied
    weak_linking = anchor_linking_summary(identified_spec; min_shared_units = 3)
    @test !weak_linking.passed
    @test weak_linking.rater_linking_status === :disconnected
    @test weak_linking.n_rater_components == 2
    @test weak_linking.n_weak_links == 1
    data_only_linking = anchor_linking_summary(identified_data)
    @test ismissing(data_only_linking.family)
    @test data_only_linking.anchor_status === :not_declared
    @test data_only_linking.n_anchors == 0
    targeted_anchor_spec = mfrm_spec(identified_data;
        thresholds = :partial_credit,
        anchors = [(block = :rater, level = "R1", value = 0.0, type = :hard)])
    targeted_linking = anchor_linking_summary(targeted_anchor_spec)
    @test targeted_linking.passed
    @test only(targeted_linking.anchor_rows).target == "R1"
    @test only(targeted_linking.anchor_rows).target_found === true
    invalid_anchor_spec = mfrm_spec(identified_data;
        thresholds = :partial_credit,
        anchors = [(block = :rater, level = "R-missing", value = 0.0, type = :hard)])
    invalid_linking = anchor_linking_summary(invalid_anchor_spec)
    @test !invalid_linking.passed
    @test invalid_linking.anchor_status === :invalid_targets
    @test invalid_linking.n_anchor_target_failures == 1
    @test only(invalid_linking.anchor_rows).status === :anchor_target_not_in_data
    invalid_anchor_audit = rating_design_audit(invalid_anchor_spec)
    @test !invalid_anchor_audit.passed
    @test invalid_anchor_audit.summary.anchor_status === :invalid_targets
    @test any(row -> row.audit === :anchor_coverage &&
        row.status === :invalid_targets &&
        row.severity === :error,
        invalid_anchor_audit.rows)
    @test_throws ArgumentError anchor_linking_summary(identified_spec; min_shared_units = 0)
    @test_throws ArgumentError mfrm_spec(identified_data;
        thresholds = :partial_credit,
        anchors = [(block = :item, value = 0.0, type = :soft)])

    gmfrm_spec = mfrm_spec(identified_data; family = :gmfrm, discrimination = :rater)
    @test gmfrm_spec.family === :gmfrm
    @test gmfrm_spec.dimensions == 1
    @test gmfrm_spec.discrimination === :rater
    @test gmfrm_spec.estimation_status === :specified_only
    @test any(row -> row.block === :item_discrimination && row.constraint === :geometric_mean_one,
        constraint_table(gmfrm_spec))
    @test any(row -> row.block === :rater_consistency && row.transform === :log_link,
        constraint_table(gmfrm_spec))
    @test any(row -> row.block === :rater_steps && row.constraint === :first_step_zero_sum_to_zero,
        constraint_table(gmfrm_spec))
    gmfrm_identification = identification_declarations(gmfrm_spec)
    @test any(row -> row.block === :item &&
        row.rule === :sum_to_zero,
        gmfrm_identification)
    @test any(row -> row.block === :item_discrimination &&
        row.rule === :geometric_mean_one &&
        row.components == (:geometric_mean_one,),
        gmfrm_identification)
    @test any(row -> row.block === :rater_steps &&
        row.rule === :fixed &&
        row.components == (:fixed, :sum_to_zero),
        gmfrm_identification)
    @test model_manifest(gmfrm_spec).spec.scope === :planned_generalized_mfrm
    @test model_manifest(gmfrm_spec).spec.status_policy.status_label === :specified_only
    @test :public_fit in model_manifest(gmfrm_spec).spec.status_policy.blocked_claims
    @test :broad_generalized_fit in model_manifest(gmfrm_spec).spec.status_policy.blocked_claims
    gmfrm_multidimensional_error = argument_error_message() do
        mfrm_spec(
            identified_data;
            family = :gmfrm,
            dimensions = 2,
            discrimination = :rater,
        )
    end
    @test occursin("family = :gmfrm is one-dimensional",
        gmfrm_multidimensional_error)
    @test occursin("family = :mgmfrm", gmfrm_multidimensional_error)

    gmfrm_item_discrimination_spec =
        mfrm_spec(identified_data; family = :gmfrm, discrimination = :item)
    gmfrm_item_fit_error = argument_error_message() do
        fit(
            gmfrm_item_discrimination_spec;
            experimental = true,
            ndraws = 1,
            warmup = 0,
            chains = 1,
        )
    end
    @test occursin("discrimination = :item", gmfrm_item_fit_error)
    @test occursin("Supported configuration:", gmfrm_item_fit_error)
    @test !occursin(r"blocked_option|supported_surface|next_gate", gmfrm_item_fit_error)

    gmfrm_backend_error = argument_error_message() do
        fit(gmfrm_spec; experimental = true, backend = :julia, ndraws = 1, warmup = 0)
    end
    @test occursin("backend = :julia", gmfrm_backend_error)
    @test occursin("backend = :advancedhmc", gmfrm_backend_error)
    @test !occursin(r"blocked_option|supported_surface|next_gate", gmfrm_backend_error)

    gmfrm_prior_error = argument_error_message() do
        fit(gmfrm_spec; experimental = true, prior = MFRMPrior(), ndraws = 1, warmup = 0)
    end
    @test occursin("prior = :MFRMPrior", gmfrm_prior_error)
    @test occursin("Omit `prior`", gmfrm_prior_error)
    @test !occursin(r"blocked_option|supported_surface|next_gate|internal_|_SourceFixturePrior",
        gmfrm_prior_error)

    gmfrm_dff_data = FacetData(
        (;
            examinee = ["E1", "E1", "E1", "E2", "E2", "E2"],
            rater = ["R1", "R2", "R1", "R1", "R2", "R1"],
            item = ["I1", "I1", "I2", "I1", "I2", "I2"],
            group = ["A", "A", "A", "A", "B", "A"],
            score = [0, 1, 2, 1, 0, 2],
        );
        person = :examinee,
        rater = :rater,
        item = :item,
        score = :score,
        group = :group,
    )
    gmfrm_dff_spec = mfrm_spec(
        gmfrm_dff_data;
        family = :gmfrm,
        discrimination = :rater,
        bias = [(:rater, :group)],
    )
    gmfrm_dff_fit_error = argument_error_message() do
        fit(gmfrm_dff_spec; experimental = true, ndraws = 1, warmup = 0)
    end
    @test occursin("dff_effects = ", gmfrm_dff_fit_error)
    @test occursin("Supported configuration:", gmfrm_dff_fit_error)
    @test !occursin(r"blocked_option|supported_surface|next_gate", gmfrm_dff_fit_error)
    gmfrm_equation = model_equation(gmfrm_spec)
    @test gmfrm_equation.family === :gmfrm
    @test !gmfrm_equation.fit_ready
    @test :item_discrimination in gmfrm_equation.required_blocks
    @test :rater_consistency in gmfrm_equation.required_blocks
    @test :identified_transform_for_item_discrimination_product_constraint in
        gmfrm_equation.implementation_gaps
    @test :literature_gmfrm_likelihood_kernel in
        gmfrm_equation.implementation_gaps
    gmfrm_preview = getdesign(gmfrm_spec; preview = true)
    @test gmfrm_preview.spec === gmfrm_spec
    @test gmfrm_preview.identification[:item] === :sum_to_zero
    @test gmfrm_preview.identification[:item_discrimination] === :geometric_mean_one
    @test gmfrm_preview.identification[:rater_consistency] === :positive
    @test gmfrm_preview.identification[:rater_steps] === :first_step_zero_sum_to_zero
    gmfrm_preview_identification = identification_declarations(gmfrm_preview)
    gmfrm_item_identification = only(filter(row ->
        row.block === :item && row.rule === :sum_to_zero,
        gmfrm_preview_identification))
    @test gmfrm_item_identification.n_parameters == 2
    @test gmfrm_item_identification.parameter_names == ["item[I1]", "item[I2]"]
    @test gmfrm_preview.parameter_names[gmfrm_preview.blocks[:item_discrimination]] == [
        "item_discrimination[item=I1]",
        "item_discrimination[item=I2]",
    ]
    @test gmfrm_preview.parameter_names[gmfrm_preview.blocks[:rater_consistency]] == [
        "rater_consistency[rater=R1]",
        "rater_consistency[rater=R2]",
    ]
    @test gmfrm_preview.parameter_names[gmfrm_preview.blocks[:rater_steps]] == [
        "rater_step[rater=R1,m=2]",
        "rater_step[rater=R2,m=2]",
    ]
    @test length(gmfrm_preview.parameter_names) == 12
    @test_throws ArgumentError design_row_table(gmfrm_spec)
    gmfrm_rows = design_row_table(gmfrm_spec; preview = true)
    @test gmfrm_rows[1].rater_parameter_name == "rater[R1]"
    @test gmfrm_rows[1].item_discrimination_parameter_name == "item_discrimination[item=I1]"
    @test gmfrm_rows[1].rater_consistency_parameter_name == "rater_consistency[rater=R1]"
    @test gmfrm_rows[2].rater_consistency_parameter_name == "rater_consistency[rater=R2]"
    @test gmfrm_rows[2].threshold_parameter_names == ["rater_step[rater=R2,m=2]"]
    @test gmfrm_rows[2].threshold_blocks == [:rater_steps]
    @test isempty(gmfrm_rows[2].discrimination_parameter_indices)
    @test isempty(gmfrm_rows[2].loading_parameter_indices)
    @test_throws ArgumentError linear_predictor_table(gmfrm_spec)
    gmfrm_predictors = linear_predictor_table(gmfrm_spec; preview = true)
    @test length(gmfrm_predictors) == identified_data.n * length(identified_data.category_levels)
    @test gmfrm_predictors[1].kernel === :gmfrm_source_aligned
    @test gmfrm_predictors[1].location_multiplier == 0
    @test isempty(gmfrm_predictors[1].step_parameter_indices)
    gmfrm_row2_cat1 = only(filter(row -> row.row == 2 && row.category == 1, gmfrm_predictors))
    @test gmfrm_row2_cat1.observed
    @test gmfrm_row2_cat1.location_multiplier == 1
    @test gmfrm_row2_cat1.rater_consistency_parameter_name == "rater_consistency[rater=R2]"
    @test gmfrm_row2_cat1.item_discrimination_parameter_name == "item_discrimination[item=I1]"
    @test gmfrm_row2_cat1.step_parameter_names == ["rater_step[rater=R2,m=2]"]
    gmfrm_row3_cat2 = only(filter(row -> row.row == 3 && row.category == 2, gmfrm_predictors))
    @test gmfrm_row3_cat2.location_multiplier == 2
    @test isequal(gmfrm_row3_cat2.step_parameter_names, ["rater_step[rater=R1,m=2]", missing])
    @test gmfrm_row3_cat2.step_blocks == [:rater_steps, :rater_steps]
    gmfrm_params = [
        0.3, -0.2,      # person locations
        0.1, -0.05,     # rater severities
        -0.2, 0.2,      # item difficulties, sum-to-zero
        2.0, 0.5,       # item discriminations, product-one
        1.2, 0.8,       # rater consistency values
        0.25, -0.1,     # free rater steps for m = 2
    ]
    gmfrm_raw_blueprint = BayesianMGMFRM._gmfrm_source_unconstrained_blueprint(gmfrm_preview)
    @test gmfrm_raw_blueprint.scope === :scalar_gmfrm_source_aligned
    @test gmfrm_raw_blueprint.status === :internal_source_fixture
    @test gmfrm_raw_blueprint.compiler_stage === :source_fixture
    @test gmfrm_raw_blueprint.fixture_only
    @test !gmfrm_raw_blueprint.fit_ready
    @test gmfrm_raw_blueprint.n_parameters == 10
    @test gmfrm_raw_blueprint.parameter_names[gmfrm_raw_blueprint.blocks[:item_free]] == ["raw_item[I1]"]
    @test gmfrm_raw_blueprint.parameter_names[gmfrm_raw_blueprint.blocks[:log_item_discrimination_free]] ==
        ["raw_log_item_discrimination[I1]"]
    gmfrm_fit_ready_blueprint =
        BayesianMGMFRM._gmfrm_fit_ready_candidate_blueprint(gmfrm_preview)
    @test gmfrm_fit_ready_blueprint.scope === :scalar_gmfrm_fit_ready_candidate
    @test gmfrm_fit_ready_blueprint.status === :internal_fit_ready_candidate
    @test gmfrm_fit_ready_blueprint.compiler_stage === :fit_ready_candidate
    @test !gmfrm_fit_ready_blueprint.fixture_only
    @test !gmfrm_fit_ready_blueprint.fit_ready
    @test gmfrm_fit_ready_blueprint.parameter_names == gmfrm_raw_blueprint.parameter_names
    @test gmfrm_fit_ready_blueprint.constrained_parameter_names ==
        gmfrm_raw_blueprint.constrained_parameter_names
    @test gmfrm_fit_ready_blueprint.blocks == gmfrm_raw_blueprint.blocks
    @test gmfrm_fit_ready_blueprint.constrained_blocks == gmfrm_raw_blueprint.constrained_blocks
    @test_throws ArgumentError fit_ready_parameter_layout(gmfrm_spec)
    gmfrm_layout = fit_ready_parameter_layout(gmfrm_spec; preview = true)
    @test gmfrm_layout.schema == "bayesianmgmfrm.fit_ready_parameter_layout.v1"
    @test gmfrm_layout.family === :gmfrm
    @test gmfrm_layout.scope === :scalar_gmfrm_fit_ready_candidate
    @test gmfrm_layout.status === :internal_fit_ready_candidate
    @test gmfrm_layout.parameterization === :raw_to_constrained
    @test gmfrm_layout.experimental_public
    @test !gmfrm_layout.public_fit
    @test !gmfrm_layout.fit_ready
    @test gmfrm_layout.raw_parameter_names == gmfrm_fit_ready_blueprint.parameter_names
    @test gmfrm_layout.constrained_parameter_names ==
        gmfrm_fit_ready_blueprint.constrained_parameter_names
    @test any(row -> row.block === :item_free &&
        row.parameter_names == ["raw_item[I1]"],
        gmfrm_layout.raw_blocks)
    @test any(row -> row.block === :item &&
        row.parameter_names == ["item[I1]", "item[I2]"],
        gmfrm_layout.constrained_blocks)
    @test any(row -> row.raw_block === :log_item_discrimination_free &&
        row.constrained_block === :item_discrimination &&
        row.transform === :geometric_mean_one_log_last,
        gmfrm_layout.transforms)
    @test_throws ArgumentError domain_compilation_summary(gmfrm_spec)
    gmfrm_domain = domain_compilation_summary(gmfrm_spec; preview = true)
    gmfrm_item_discrimination_domain = only(filter(row ->
        row.block === :item_discrimination &&
        row.compiled_role === :discrimination_block,
        gmfrm_domain))
    @test gmfrm_item_discrimination_domain.raw_block === :log_item_discrimination_free
    @test gmfrm_item_discrimination_domain.constraint === :geometric_mean_one
    @test gmfrm_item_discrimination_domain.prior_block === :log_item_discrimination
    @test gmfrm_item_discrimination_domain.prior === :lognormal_or_hierarchical
    @test !gmfrm_item_discrimination_domain.fit_ready
    @test gmfrm_item_discrimination_domain.experimental_public
    gmfrm_audit = model_surface_audit(gmfrm_spec)
    @test model_manifest(gmfrm_spec).spec.model_surface_audit == gmfrm_audit
    gmfrm_consistency_audit = only(filter(row ->
        row.block === :rater_consistency &&
        row.compiled_role === :discrimination_block,
        gmfrm_audit))
    @test gmfrm_consistency_audit.current_status === :specified_only
    @test !gmfrm_consistency_audit.public_fit
    @test gmfrm_consistency_audit.source_symbol == "alpha_r"
    @test gmfrm_consistency_audit.direct_interpretation ==
        "positive rater consistency multiplier"
    @test gmfrm_consistency_audit.raw_coordinate === :log_rater_consistency
    @test gmfrm_consistency_audit.constraint === :positive
    @test gmfrm_consistency_audit.prior_scale === :log_consistency_sd
    @test gmfrm_consistency_audit.report_label === :rater_consistency
    @test :public_fit in gmfrm_consistency_audit.blocked_claims
    gmfrm_scoring_domain = only(filter(row ->
        row.compiled_role === :scoring_vector,
        gmfrm_domain))
    @test gmfrm_scoring_domain.block === :rater_steps
    @test gmfrm_scoring_domain.parameter_names == [
        "rater_step[rater=R1,m=2]",
        "rater_step[rater=R2,m=2]",
    ]
    @test gmfrm_scoring_domain.scoring_vector == identified_data.category_levels
    gmfrm_preview_manifest = model_manifest(gmfrm_preview)
    gmfrm_raw_manifest = gmfrm_preview_manifest.design.raw_parameterization
    @test gmfrm_raw_manifest.schema == "bayesianmgmfrm.raw_parameterization.v1"
    @test gmfrm_raw_manifest.family === :gmfrm
    @test gmfrm_raw_manifest.status === :internal_source_fixture
    @test gmfrm_raw_manifest.public_fit === false
    @test gmfrm_raw_manifest.fixture_only
    @test !gmfrm_raw_manifest.fit_ready
    @test gmfrm_raw_manifest.density_space === :raw_unconstrained
    @test gmfrm_raw_manifest.prior_policy === :independent_normal_raw_coordinates
    @test gmfrm_raw_manifest.jacobian_policy === :none_raw_coordinate_density
    @test gmfrm_raw_manifest.n_raw_parameters == gmfrm_raw_blueprint.n_parameters
    @test gmfrm_raw_manifest.raw_parameter_names == gmfrm_raw_blueprint.parameter_names
    gmfrm_item_transform = only(filter(row -> row.raw_block === :item_free,
        gmfrm_raw_manifest.transforms))
    @test gmfrm_item_transform.constrained_block === :item
    @test gmfrm_item_transform.transform === :sum_to_zero_last
    @test gmfrm_item_transform.constraint === :sum_to_zero
    @test gmfrm_item_transform.raw_parameter_names == ["raw_item[I1]"]
    @test gmfrm_item_transform.constrained_parameter_names == ["item[I1]", "item[I2]"]
    gmfrm_discrimination_transform = only(filter(row -> row.raw_block === :log_item_discrimination_free,
        gmfrm_raw_manifest.transforms))
    @test gmfrm_discrimination_transform.transform === :geometric_mean_one_log_last
    @test gmfrm_discrimination_transform.prior_block === :log_item_discrimination
    @test gmfrm_discrimination_transform.jacobian_policy === :none_raw_coordinate_density
    gmfrm_candidate_manifest = gmfrm_raw_manifest.promotion_candidate
    @test gmfrm_candidate_manifest.schema == "bayesianmgmfrm.gmfrm_promotion_candidate.v1"
    @test gmfrm_candidate_manifest.family === :gmfrm
    @test gmfrm_candidate_manifest.scope === :scalar_gmfrm_fit_ready_candidate
    @test gmfrm_candidate_manifest.status === :internal_promotion_candidate
    @test gmfrm_candidate_manifest.public_fit === false
    @test !gmfrm_candidate_manifest.fit_ready
    @test !gmfrm_candidate_manifest.fixture_only
    @test gmfrm_candidate_manifest.compiler_stage === :fit_ready_candidate
    @test gmfrm_candidate_manifest.source_oracle === :scalar_gmfrm_source_aligned
    @test gmfrm_candidate_manifest.transform_ready
    @test gmfrm_candidate_manifest.logdensity_ready
    @test gmfrm_candidate_manifest.bridge_oracle_ready
    @test gmfrm_candidate_manifest.bridge_direct_ready
    @test gmfrm_candidate_manifest.direct_pointwise_ready
    @test gmfrm_candidate_manifest.sampler_smoke_ready
    @test gmfrm_candidate_manifest.production_diagnostics_ready
    @test gmfrm_candidate_manifest.candidate_chain_study_ready
    @test gmfrm_candidate_manifest.stress_chain_grid_ready
    @test gmfrm_candidate_manifest.recovery_smoke_ready
    @test gmfrm_candidate_manifest.baseline_comparison_ready
    @test gmfrm_candidate_manifest.baseline_calibration_grid_ready
    @test gmfrm_candidate_manifest.interval_decision_grid_ready
    @test gmfrm_candidate_manifest.sparse_design_grid_ready
    @test gmfrm_candidate_manifest.waic_influence_review_ready
    @test gmfrm_candidate_manifest.psis_loo_review_ready
    @test gmfrm_candidate_manifest.exact_loo_or_kfold_review_ready
    @test gmfrm_candidate_manifest.guarded_exposure_review_ready
    @test gmfrm_candidate_manifest.guarded_fit_api_dry_run_ready
    @test gmfrm_candidate_manifest.guarded_fit_method_wiring_ready
    @test gmfrm_candidate_manifest.experimental_fit_validation_grid_ready
    @test gmfrm_candidate_manifest.posterior_predictive_grid_ready
    @test gmfrm_candidate_manifest.sparse_pathology_recovery_grid_ready
    @test gmfrm_candidate_manifest.prior_likelihood_sensitivity_grid_ready
    @test gmfrm_candidate_manifest.real_data_case_study_ready
    @test gmfrm_candidate_manifest.claim_recovery_reproduction_archive_ready
    @test gmfrm_candidate_manifest.broader_experimental_exposure_decision_review_ready
    @test gmfrm_candidate_manifest.public_target_label ===
        :guarded_scalar_gmfrm_logdensity
    @test gmfrm_candidate_manifest.public_target_description ==
        "guarded scalar GMFRM log density"
    @test gmfrm_candidate_manifest.internal_target_constructor ===
        :_gmfrm_promotion_candidate_logdensity
    @test gmfrm_candidate_manifest.internal_diagnostic_constructor ===
        :_gmfrm_promotion_candidate_diagnostics
    @test gmfrm_candidate_manifest.internal_sampler_diagnostic_constructor ===
        :_gmfrm_promotion_candidate_sampler_diagnostics
    gmfrm_rater_step_policy =
        gmfrm_candidate_manifest.rater_step_public_option_policy
    @test gmfrm_rater_step_policy.schema ==
        "bayesianmgmfrm.gmfrm_rater_step_public_option_policy.v1"
    @test gmfrm_rater_step_policy.source_block === :rater_steps
    @test gmfrm_rater_step_policy.source_block_status ===
        :internal_source_model_block
    @test gmfrm_rater_step_policy.internal_block_enabled
    @test gmfrm_rater_step_policy.public_option === :rater_steps
    @test !gmfrm_rater_step_policy.public_keyword_enabled
    @test gmfrm_rater_step_policy.public_option_status ===
        :blocked_until_policy_gate
    @test gmfrm_rater_step_policy.blocker ===
        :rater_step_public_option_policy_not_promoted
    @test gmfrm_rater_step_policy.next_gate ===
        :rater_step_public_option_policy
    gmfrm_item_discrimination_decision =
        gmfrm_candidate_manifest.item_discrimination_promotion_decision
    @test gmfrm_item_discrimination_decision.schema ==
        "bayesianmgmfrm.gmfrm_item_discrimination_promotion_decision.v1"
    @test gmfrm_item_discrimination_decision.decision ===
        :keep_preview_only_for_v0_1_1
    @test gmfrm_item_discrimination_decision.source_block ===
        :item_discrimination
    @test gmfrm_item_discrimination_decision.source_block_status ===
        :enabled_within_guarded_rater_consistency_surface
    @test !gmfrm_item_discrimination_decision.public_fit_enabled
    @test !gmfrm_item_discrimination_decision.internal_promotion_target_enabled
    @test gmfrm_item_discrimination_decision.blocked_option ===
        :discrimination
    @test gmfrm_item_discrimination_decision.blocked_value === :item
    @test gmfrm_item_discrimination_decision.next_gate ===
        :item_discrimination_promotion_decision
    gmfrm_raw_prior_controls =
        gmfrm_candidate_manifest.raw_prior_control_manifest
    @test gmfrm_raw_prior_controls.schema ==
        "bayesianmgmfrm.generalized_raw_prior_control_manifest.v1"
    @test gmfrm_raw_prior_controls.family === :gmfrm
    @test gmfrm_raw_prior_controls.scope === :scalar_gmfrm_fit_ready_candidate
    @test gmfrm_raw_prior_controls.prior_policy ===
        :independent_normal_raw_coordinates
    @test !gmfrm_raw_prior_controls.direct_scale_priors
    @test gmfrm_raw_prior_controls.jacobian_policy ===
        :none_raw_coordinate_density
    @test gmfrm_raw_prior_controls.n_rows == 7
    @test gmfrm_raw_prior_controls.summary.raw_rater_consistency_control_recorded
    @test gmfrm_raw_prior_controls.summary.item_discrimination_source_control_recorded
    @test !gmfrm_raw_prior_controls.summary.direct_scale_generalized_priors_enabled
    @test any(row -> row.raw_block === :log_rater_consistency &&
        row.constrained_block === :rater_consistency &&
        row.scale_parameter === :log_consistency_sd &&
        ismissing(row.scale) &&
        row.public_surface_role === :guarded_scalar_gmfrm_core,
        gmfrm_raw_prior_controls.rows)
    @test any(row -> row.raw_block === :log_item_discrimination_free &&
        row.constrained_block === :item_discrimination &&
        row.scale_parameter === :log_discrimination_sd &&
        row.public_surface_role ===
            :source_block_active_public_item_target_preview_only,
        gmfrm_raw_prior_controls.rows)
    @test any(row -> row.constrained_block ===
            :direct_scale_generalized_priors &&
        row.status === :blocked &&
        row.jacobian_policy === :requires_future_log_jacobian_policy,
        gmfrm_raw_prior_controls.rows)
    @test gmfrm_candidate_manifest.target_constructor === :_gmfrm_promotion_candidate_logdensity
    @test gmfrm_candidate_manifest.diagnostic_constructor === :_gmfrm_promotion_candidate_diagnostics
    @test gmfrm_candidate_manifest.sampler_diagnostic_constructor ===
        :_gmfrm_promotion_candidate_sampler_diagnostics
    @test gmfrm_candidate_manifest.pointwise_fixture_constructor === :_gmfrm_promotion_candidate_pointwise_fixture
    @test gmfrm_candidate_manifest.compiler_blueprint_constructor ===
        :_gmfrm_fit_ready_candidate_blueprint
    @test gmfrm_candidate_manifest.fit_ready_compiler_ready
    @test gmfrm_candidate_manifest.experimental_public_ready
    @test gmfrm_candidate_manifest.raw_parameter_names == gmfrm_raw_blueprint.parameter_names
    gmfrm_fit_ready_manifest = gmfrm_candidate_manifest.fit_ready_compiler
    @test gmfrm_fit_ready_manifest.schema ==
        "bayesianmgmfrm.gmfrm_fit_ready_compiler_candidate.v1"
    @test gmfrm_fit_ready_manifest.family === :gmfrm
    @test gmfrm_fit_ready_manifest.scope === :scalar_gmfrm_fit_ready_candidate
    @test gmfrm_fit_ready_manifest.status === :internal_fit_ready_candidate
    @test !gmfrm_fit_ready_manifest.public_fit
    @test !gmfrm_fit_ready_manifest.fit_ready
    @test !gmfrm_fit_ready_manifest.fixture_only
    @test gmfrm_fit_ready_manifest.compiler_stage === :fit_ready_candidate
    @test gmfrm_fit_ready_manifest.source_oracle === :scalar_gmfrm_source_aligned
    @test gmfrm_fit_ready_manifest.public_target_label ===
        :guarded_scalar_gmfrm_logdensity
    @test gmfrm_fit_ready_manifest.public_target_description ==
        "guarded scalar GMFRM log density"
    @test gmfrm_fit_ready_manifest.internal_target_constructor ===
        :_gmfrm_promotion_candidate_logdensity
    @test gmfrm_fit_ready_manifest.rater_step_public_option_policy.next_gate ===
        :rater_step_public_option_policy
    @test gmfrm_fit_ready_manifest.item_discrimination_promotion_decision.decision ===
        :keep_preview_only_for_v0_1_1
    @test gmfrm_fit_ready_manifest.item_discrimination_promotion_decision.next_gate ===
        :item_discrimination_promotion_decision
    @test :public_rater_steps in
        gmfrm_fit_ready_manifest.unsupported_public_options
    @test :item_discrimination_public_target in
        gmfrm_fit_ready_manifest.unsupported_public_options
    @test gmfrm_fit_ready_manifest.direct_prior_policy ===
        :not_enabled_raw_coordinate_priors_only
    @test gmfrm_fit_ready_manifest.raw_prior_control_manifest.schema ==
        "bayesianmgmfrm.generalized_raw_prior_control_manifest.v1"
    @test any(row -> row.raw_block === :log_rater_consistency &&
        row.scale_parameter === :log_consistency_sd,
        gmfrm_fit_ready_manifest.raw_prior_control_manifest.rows)
    @test gmfrm_fit_ready_manifest.raw_parameter_names == gmfrm_raw_blueprint.parameter_names
    @test gmfrm_fit_ready_manifest.constrained_parameter_names == gmfrm_preview.parameter_names
    @test any(row -> row.raw_block === :log_item_discrimination_free &&
        row.constrained_block === :item_discrimination &&
        row.constraint === :geometric_mean_one,
        gmfrm_fit_ready_manifest.constraints)
    @test :direct_scale_priors in gmfrm_fit_ready_manifest.unsupported_public_options
    gmfrm_direct_manifest = gmfrm_candidate_manifest.direct_parameterization
    @test gmfrm_direct_manifest.schema ==
        "bayesianmgmfrm.gmfrm_direct_parameterization_candidate.v1"
    @test gmfrm_direct_manifest.family === :gmfrm
    @test gmfrm_direct_manifest.scope === :scalar_gmfrm_fit_ready_candidate
    @test gmfrm_direct_manifest.status === :internal_promotion_candidate
    @test !gmfrm_direct_manifest.fixture_only
    @test gmfrm_direct_manifest.density_space === :constrained_direct
    @test gmfrm_direct_manifest.prior_policy === :derived_from_raw_candidate_no_direct_prior
    @test gmfrm_direct_manifest.jacobian_policy === :not_applicable_for_direct_likelihood
    @test gmfrm_direct_manifest.parameter_names == gmfrm_raw_blueprint.constrained_parameter_names
    @test any(row -> row.block === :item_discrimination && row.parameter_names == [
            "item_discrimination[item=I1]",
            "item_discrimination[item=I2]",
        ], gmfrm_direct_manifest.blocks)
    @test any(row -> row.raw_block === :log_item_discrimination_free &&
        row.constrained_block === :item_discrimination,
        gmfrm_direct_manifest.source_transforms)
    @test any(row -> row.gate === :bridge_oracle_check && row.status === :done,
        gmfrm_candidate_manifest.candidate_gates)
    @test any(row -> row.gate === :fit_ready_compiler_manifest && row.status === :done,
        gmfrm_candidate_manifest.candidate_gates)
    @test any(row -> row.gate === :bridge_direct_parameter_check && row.status === :done,
        gmfrm_candidate_manifest.candidate_gates)
    @test any(row -> row.gate === :direct_parameter_metadata && row.status === :done,
        gmfrm_candidate_manifest.candidate_gates)
    @test any(row -> row.gate === :raw_to_direct_transform && row.status === :done,
        gmfrm_candidate_manifest.candidate_gates)
    @test any(row -> row.gate === :direct_pointwise_fixture && row.status === :done,
        gmfrm_candidate_manifest.candidate_gates)
    @test any(row -> row.gate === :public_fit_api && row.status === :blocked,
        gmfrm_candidate_manifest.candidate_gates)
    @test any(row -> row.gate === :production_diagnostics && row.status === :done,
        gmfrm_candidate_manifest.candidate_gates)
    @test any(row -> row.gate === :candidate_chain_study &&
        row.status === :done &&
        row.evidence === :gmfrm_candidate_chain_study_fixture,
        gmfrm_candidate_manifest.candidate_gates)
    @test any(row -> row.gate === :stress_chain_grid &&
        row.status === :done &&
        row.evidence === :gmfrm_stress_chain_grid_fixture,
        gmfrm_candidate_manifest.candidate_gates)
    @test any(row -> row.gate === :recovery_smoke_study &&
        row.status === :done &&
        row.evidence === :gmfrm_recovery_smoke_fixture,
        gmfrm_candidate_manifest.candidate_gates)
    @test any(row -> row.gate === :baseline_comparison &&
        row.status === :done &&
        row.evidence === :gmfrm_baseline_comparison_fixture,
        gmfrm_candidate_manifest.candidate_gates)
    @test any(row -> row.gate === :baseline_calibration_grid &&
        row.status === :done &&
        row.evidence === :gmfrm_baseline_calibration_grid_fixture,
        gmfrm_candidate_manifest.candidate_gates)
    @test any(row -> row.gate === :interval_decision_grid &&
        row.status === :done &&
        row.evidence === :gmfrm_interval_decision_grid_fixture,
        gmfrm_candidate_manifest.candidate_gates)
    @test any(row -> row.gate === :sparse_design_grid &&
        row.status === :done &&
        row.evidence === :gmfrm_sparse_design_grid_fixture,
        gmfrm_candidate_manifest.candidate_gates)
    @test any(row -> row.gate === :waic_influence_review &&
        row.status === :done &&
        row.evidence === :gmfrm_waic_influence_review_fixture,
        gmfrm_candidate_manifest.candidate_gates)
    @test any(row -> row.gate === :psis_loo_review &&
        row.status === :done &&
        row.evidence === :gmfrm_psis_loo_review_fixture,
        gmfrm_candidate_manifest.candidate_gates)
    @test any(row -> row.gate === :exact_loo_or_kfold_review &&
        row.status === :done &&
        row.evidence === :gmfrm_exact_loo_or_kfold_review_fixture,
        gmfrm_candidate_manifest.candidate_gates)
    @test any(row -> row.gate === :guarded_exposure_review &&
        row.status === :done &&
        row.evidence === :gmfrm_guarded_exposure_review_fixture,
        gmfrm_candidate_manifest.candidate_gates)
    @test any(row -> row.gate === :guarded_fit_api_dry_run &&
        row.status === :done &&
        row.evidence === :gmfrm_guarded_fit_api_dry_run_fixture,
        gmfrm_candidate_manifest.candidate_gates)
    @test any(row -> row.gate === :guarded_fit_method_wiring &&
        row.status === :done &&
        row.evidence === :gmfrm_guarded_fit_method_wiring_fixture,
        gmfrm_candidate_manifest.candidate_gates)
    @test any(row -> row.gate === :experimental_fit_validation_grid &&
        row.status === :done &&
        row.evidence === :gmfrm_experimental_fit_validation_grid_fixture,
        gmfrm_candidate_manifest.candidate_gates)
    @test any(row -> row.gate === :posterior_predictive_grid &&
        row.status === :done &&
        row.evidence === :gmfrm_posterior_predictive_grid_fixture,
        gmfrm_candidate_manifest.candidate_gates)
    @test any(row -> row.gate === :sparse_pathology_recovery_grid &&
        row.status === :done &&
        row.evidence === :gmfrm_sparse_pathology_recovery_grid_fixture,
        gmfrm_candidate_manifest.candidate_gates)
    @test any(row -> row.gate === :prior_likelihood_sensitivity_grid &&
        row.status === :done &&
        row.evidence === :gmfrm_prior_likelihood_sensitivity_grid_fixture,
        gmfrm_candidate_manifest.candidate_gates)
    @test any(row -> row.gate === :real_data_case_study &&
        row.status === :done &&
        row.evidence === :gmfrm_real_data_case_study_fixture,
        gmfrm_candidate_manifest.candidate_gates)
    @test any(row -> row.gate === :claim_recovery_reproduction_archive &&
        row.status === :done &&
        row.evidence === :gmfrm_claim_recovery_reproduction_archive_fixture,
        gmfrm_candidate_manifest.candidate_gates)
    @test any(row -> row.gate === :broader_experimental_exposure_decision_review &&
        row.status === :done &&
        row.evidence === :gmfrm_broader_experimental_exposure_decision_review_fixture,
        gmfrm_candidate_manifest.candidate_gates)
    @test any(row -> row.gate === :direct_scale_prior_jacobian_policy &&
        row.status === :done &&
        row.evidence === :raw_prior_jacobian_policy_decision,
        gmfrm_candidate_manifest.candidate_gates)
    @test any(row -> row.gate === :experimental_public_api &&
        row.status === :done &&
        row.evidence === :gmfrm_experimental_public_api_decision,
        gmfrm_candidate_manifest.candidate_gates)
    gmfrm_experimental_decision = gmfrm_candidate_manifest.experimental_public_api
    @test gmfrm_experimental_decision.schema ==
        "bayesianmgmfrm.gmfrm_experimental_public_api_decision.v1"
    @test gmfrm_experimental_decision.family === :gmfrm
    @test gmfrm_experimental_decision.scope === :scalar_gmfrm_fit_ready_candidate
    @test gmfrm_experimental_decision.status === :experimental_public
    @test gmfrm_experimental_decision.decision === :enable_guarded_experimental
    @test gmfrm_experimental_decision.public_fit
    @test gmfrm_experimental_decision.experimental_public
    @test gmfrm_experimental_decision.fit_ready
    @test gmfrm_experimental_decision.proposed_entrypoint ==
        "BayesianMGMFRM.Experimental.fit(spec)"
    @test gmfrm_experimental_decision.legacy_entrypoint ==
        "BayesianMGMFRM.fit(spec; experimental = true)"
    @test gmfrm_experimental_decision.public_target_label ===
        :guarded_scalar_gmfrm_logdensity
    @test gmfrm_experimental_decision.public_target_description ==
        "guarded scalar GMFRM log density"
    @test gmfrm_experimental_decision.internal_target_constructor ===
        :_gmfrm_promotion_candidate_logdensity
    @test gmfrm_experimental_decision.internal_sampler_diagnostic_constructor ===
        :_gmfrm_promotion_candidate_sampler_diagnostics
    @test gmfrm_experimental_decision.rater_step_public_option_policy.schema ==
        "bayesianmgmfrm.gmfrm_rater_step_public_option_policy.v1"
    @test gmfrm_experimental_decision.rater_step_public_option_policy.public_option ===
        :rater_steps
    @test !gmfrm_experimental_decision.rater_step_public_option_policy.public_keyword_enabled
    @test gmfrm_experimental_decision.rater_step_public_option_policy.next_gate ===
        :rater_step_public_option_policy
    @test gmfrm_experimental_decision.item_discrimination_promotion_decision.schema ==
        "bayesianmgmfrm.gmfrm_item_discrimination_promotion_decision.v1"
    @test gmfrm_experimental_decision.item_discrimination_promotion_decision.decision ===
        :keep_preview_only_for_v0_1_1
    @test gmfrm_experimental_decision.item_discrimination_promotion_decision.next_gate ===
        :item_discrimination_promotion_decision
    @test gmfrm_experimental_decision.target_constructor ===
        :_gmfrm_promotion_candidate_logdensity
    @test gmfrm_experimental_decision.sampler_diagnostic_constructor ===
        :_gmfrm_promotion_candidate_sampler_diagnostics
    @test gmfrm_experimental_decision.candidate_chain_study_artifact ==
        "test/fixtures/gmfrm_candidate_chain_study.json"
    @test gmfrm_experimental_decision.stress_chain_grid_artifact ==
        "test/fixtures/gmfrm_stress_chain_grid.json"
    @test gmfrm_experimental_decision.recovery_smoke_artifact ==
        "test/fixtures/gmfrm_recovery_smoke.json"
    @test gmfrm_experimental_decision.baseline_comparison_artifact ==
        "test/fixtures/gmfrm_baseline_comparison.json"
    @test gmfrm_experimental_decision.baseline_calibration_grid_artifact ==
        "test/fixtures/gmfrm_baseline_calibration_grid.json"
    @test gmfrm_experimental_decision.interval_decision_grid_artifact ==
        "test/fixtures/gmfrm_interval_decision_grid.json"
    @test gmfrm_experimental_decision.sparse_design_grid_artifact ==
        "test/fixtures/gmfrm_sparse_design_grid.json"
    @test gmfrm_experimental_decision.waic_influence_review_artifact ==
        "test/fixtures/gmfrm_waic_influence_review.json"
    @test gmfrm_experimental_decision.psis_loo_review_artifact ==
        "test/fixtures/gmfrm_psis_loo_review.json"
    @test gmfrm_experimental_decision.exact_loo_or_kfold_review_artifact ==
        "test/fixtures/gmfrm_exact_loo_or_kfold_review.json"
    @test gmfrm_experimental_decision.guarded_exposure_review_artifact ==
        "test/fixtures/gmfrm_guarded_exposure_review.json"
    @test gmfrm_experimental_decision.guarded_fit_api_dry_run_artifact ==
        "test/fixtures/gmfrm_guarded_fit_api_dry_run.json"
    @test gmfrm_experimental_decision.guarded_fit_method_wiring_artifact ==
        "test/fixtures/gmfrm_guarded_fit_method_wiring.json"
    @test gmfrm_experimental_decision.experimental_fit_validation_grid_artifact ==
        "test/fixtures/gmfrm_experimental_fit_validation_grid.json"
    @test gmfrm_experimental_decision.posterior_predictive_grid_artifact ==
        "test/fixtures/gmfrm_posterior_predictive_grid.json"
    @test gmfrm_experimental_decision.sparse_pathology_recovery_grid_artifact ==
        "test/fixtures/gmfrm_sparse_pathology_recovery_grid.json"
    @test gmfrm_experimental_decision.prior_likelihood_sensitivity_grid_artifact ==
        "test/fixtures/gmfrm_prior_likelihood_sensitivity_grid.json"
    @test gmfrm_experimental_decision.real_data_case_study_artifact ==
        "test/fixtures/gmfrm_real_data_case_study.json"
    @test gmfrm_experimental_decision.claim_recovery_reproduction_archive_artifact ==
        "test/fixtures/gmfrm_claim_recovery_reproduction_archive.json"
    @test gmfrm_experimental_decision.broader_experimental_exposure_decision_review_artifact ==
        "test/fixtures/gmfrm_broader_experimental_exposure_decision_review.json"
    @test gmfrm_experimental_decision.mgmfrm_baseline_comparison_artifact ==
        "test/fixtures/mgmfrm_baseline_comparison.json"
    @test gmfrm_experimental_decision.mgmfrm_sparse_recovery_grid_artifact ==
        "test/fixtures/mgmfrm_sparse_recovery_grid.json"
    @test gmfrm_experimental_decision.dff_estimand_validation_grid_artifact ==
        "test/fixtures/gmfrm_dff_estimand_validation_grid.json"
    @test gmfrm_experimental_decision.manuscript_scale_simulation_grid_artifact ==
        "test/fixtures/gmfrm_manuscript_scale_simulation_grid.json"
    @test gmfrm_experimental_decision.baseline_comparison_interpretation.status ===
        :initial_smoke_done
    @test gmfrm_experimental_decision.baseline_comparison_interpretation.comparison_target ===
        :same_observation_waic
    @test gmfrm_experimental_decision.baseline_comparison_interpretation.interpretation ===
        :inconclusive_high_variance_smoke
    @test gmfrm_experimental_decision.baseline_comparison_interpretation.public_exposure_support ===
        :insufficient_alone
    @test gmfrm_experimental_decision.baseline_comparison_interpretation.required_followup ===
        :satisfied_by_baseline_calibration_grid_artifact
    @test gmfrm_experimental_decision.baseline_calibration_grid_interpretation.status ===
        :grid_recorded
    @test gmfrm_experimental_decision.baseline_calibration_grid_interpretation.comparison_target ===
        :same_observation_waic_and_expected_score_calibration
    @test gmfrm_experimental_decision.baseline_calibration_grid_interpretation.interpretation ===
        :all_scenarios_passed_with_high_variance_waic_warnings
    @test gmfrm_experimental_decision.baseline_calibration_grid_interpretation.public_exposure_support ===
        :reviewed_insufficient_for_public_fit
    @test gmfrm_experimental_decision.baseline_calibration_grid_interpretation.required_followup ===
        :satisfied_by_interval_decision_grid_artifact
    @test gmfrm_experimental_decision.interval_decision_grid_interpretation.status ===
        :grid_recorded
    @test gmfrm_experimental_decision.interval_decision_grid_interpretation.comparison_target ===
        :direct_parameter_interval_coverage_and_keep_internal_stability
    @test gmfrm_experimental_decision.interval_decision_grid_interpretation.interpretation ===
        :intervals_finite_and_keep_internal_decision_stable
    @test gmfrm_experimental_decision.interval_decision_grid_interpretation.public_exposure_support ===
        :satisfied_for_sparse_design_grid_followup
    @test gmfrm_experimental_decision.interval_decision_grid_interpretation.required_followup ===
        :satisfied_by_sparse_design_grid_artifact
    @test gmfrm_experimental_decision.sparse_design_grid_interpretation.status ===
        :grid_recorded
    @test gmfrm_experimental_decision.sparse_design_grid_interpretation.comparison_target ===
        :sparse_connected_design_validation_interval_and_decision_stability
    @test gmfrm_experimental_decision.sparse_design_grid_interpretation.interpretation ===
        :sparse_designs_passed_with_recorded_validation_warnings
    @test gmfrm_experimental_decision.sparse_design_grid_interpretation.public_exposure_support ===
        :satisfied_for_waic_influence_followup
    @test gmfrm_experimental_decision.sparse_design_grid_interpretation.required_followup ===
        :satisfied_by_waic_influence_review_artifact
    @test gmfrm_experimental_decision.waic_influence_review_interpretation.status ===
        :review_recorded
    @test gmfrm_experimental_decision.waic_influence_review_interpretation.comparison_target ===
        :pointwise_waic_influence_and_flagged_observation_sensitivity
    @test gmfrm_experimental_decision.waic_influence_review_interpretation.interpretation ===
        :flagged_observation_removal_changes_some_model_ranks
    @test gmfrm_experimental_decision.waic_influence_review_interpretation.public_exposure_support ===
        :satisfied_for_psis_loo_followup
    @test gmfrm_experimental_decision.waic_influence_review_interpretation.required_followup ===
        :satisfied_by_psis_loo_review_artifact
    @test gmfrm_experimental_decision.psis_loo_review_interpretation.status ===
        :review_recorded
    @test gmfrm_experimental_decision.psis_loo_review_interpretation.comparison_target ===
        :raw_importance_loo_pareto_k_screen
    @test gmfrm_experimental_decision.psis_loo_review_interpretation.interpretation ===
        :high_pareto_k_requires_exact_loo_or_kfold
    @test gmfrm_experimental_decision.psis_loo_review_interpretation.public_exposure_support ===
        :satisfied_for_exact_loo_or_kfold_followup
    @test gmfrm_experimental_decision.psis_loo_review_interpretation.required_followup ===
        :satisfied_by_exact_loo_or_kfold_review_artifact
    @test gmfrm_experimental_decision.exact_loo_or_kfold_review_interpretation.status ===
        :review_recorded
    @test gmfrm_experimental_decision.exact_loo_or_kfold_review_interpretation.comparison_target ===
        :heldout_observation_kfold_refit_log_score
    @test gmfrm_experimental_decision.exact_loo_or_kfold_review_interpretation.interpretation ===
        :kfold_refit_review_satisfied_exact_loo_followup
    @test gmfrm_experimental_decision.exact_loo_or_kfold_review_interpretation.public_exposure_support ===
        :satisfied_for_guarded_fit_api_dry_run_followup
    @test gmfrm_experimental_decision.exact_loo_or_kfold_review_interpretation.required_followup ===
        :satisfied_by_guarded_fit_api_dry_run_artifact
    @test gmfrm_experimental_decision.guarded_exposure_review_interpretation.status ===
        :review_recorded
    @test gmfrm_experimental_decision.guarded_exposure_review_interpretation.review_target ===
        :experimental_public_scalar_gmfrm
    @test gmfrm_experimental_decision.guarded_exposure_review_interpretation.interpretation ===
        :local_evidence_reviewed_full_archive_recorded_and_broader_exposure_decision_recorded
    @test gmfrm_experimental_decision.guarded_exposure_review_interpretation.public_exposure_support ===
        :guarded_scalar_gmfrm_only
    @test gmfrm_experimental_decision.guarded_exposure_review_interpretation.required_followup ===
        :manual_publication_or_registration_by_user_only
    @test gmfrm_experimental_decision.guarded_fit_api_dry_run_interpretation.status ===
        :dry_run_recorded
    @test gmfrm_experimental_decision.guarded_fit_api_dry_run_interpretation.review_target ===
        :guarded_experimental_scalar_gmfrm_fit_entrypoint
    @test gmfrm_experimental_decision.guarded_fit_api_dry_run_interpretation.interpretation ===
        :guarded_entrypoint_contract_dry_run_passed_but_method_not_wired
    @test gmfrm_experimental_decision.guarded_fit_api_dry_run_interpretation.public_exposure_support ===
        :satisfied_by_guarded_fit_method_wiring
    @test gmfrm_experimental_decision.guarded_fit_api_dry_run_interpretation.required_followup ===
        :satisfied_by_guarded_fit_method_wiring
    @test gmfrm_experimental_decision.guarded_fit_method_wiring_interpretation.status ===
        :method_wired
    @test gmfrm_experimental_decision.guarded_fit_method_wiring_interpretation.review_target ===
        :guarded_experimental_scalar_gmfrm_fit_entrypoint
    @test gmfrm_experimental_decision.guarded_fit_method_wiring_interpretation.interpretation ===
        :scalar_gmfrm_guarded_experimental_fit_method_enabled
    @test gmfrm_experimental_decision.guarded_fit_method_wiring_interpretation.public_exposure_support ===
        :satisfied_for_experimental_fit_validation_grid_followup
    @test gmfrm_experimental_decision.guarded_fit_method_wiring_interpretation.required_followup ===
        :experimental_fit_validation_grid
    @test gmfrm_experimental_decision.experimental_fit_validation_grid_interpretation.status ===
        :grid_recorded
    @test gmfrm_experimental_decision.experimental_fit_validation_grid_interpretation.review_target ===
        :guarded_experimental_scalar_gmfrm_fit_entrypoint
    @test gmfrm_experimental_decision.experimental_fit_validation_grid_interpretation.interpretation ===
        :guarded_scalar_gmfrm_experimental_fit_validation_grid_passed_ppc_and_sparse_pathology_checked
    @test gmfrm_experimental_decision.experimental_fit_validation_grid_interpretation.public_exposure_support ===
        :satisfied_by_sparse_pathology_recovery_grid
    @test gmfrm_experimental_decision.experimental_fit_validation_grid_interpretation.required_followup ===
        :scalar_gmfrm_prior_likelihood_sensitivity_grid
    @test gmfrm_experimental_decision.posterior_predictive_grid_interpretation.status ===
        :grid_recorded
    @test gmfrm_experimental_decision.posterior_predictive_grid_interpretation.review_target ===
        :guarded_experimental_scalar_gmfrm_fit_entrypoint
    @test gmfrm_experimental_decision.posterior_predictive_grid_interpretation.interpretation ===
        :guarded_scalar_gmfrm_posterior_predictive_grid_passed
    @test gmfrm_experimental_decision.posterior_predictive_grid_interpretation.public_exposure_support ===
        :satisfied_by_sparse_pathology_recovery_grid
    @test gmfrm_experimental_decision.posterior_predictive_grid_interpretation.required_followup ===
        :scalar_gmfrm_prior_likelihood_sensitivity_grid
    @test gmfrm_experimental_decision.sparse_pathology_recovery_grid_interpretation.status ===
        :grid_recorded
    @test gmfrm_experimental_decision.sparse_pathology_recovery_grid_interpretation.review_target ===
        :guarded_experimental_scalar_gmfrm_fit_entrypoint
    @test gmfrm_experimental_decision.sparse_pathology_recovery_grid_interpretation.interpretation ===
        :guarded_scalar_gmfrm_sparse_pathology_recovery_grid_passed
    @test gmfrm_experimental_decision.sparse_pathology_recovery_grid_interpretation.public_exposure_support ===
        :satisfied_by_prior_likelihood_sensitivity_grid
    @test gmfrm_experimental_decision.sparse_pathology_recovery_grid_interpretation.required_followup ===
        :scalar_gmfrm_real_data_case_study
    @test gmfrm_experimental_decision.prior_likelihood_sensitivity_grid_interpretation.status ===
        :grid_recorded
    @test gmfrm_experimental_decision.prior_likelihood_sensitivity_grid_interpretation.review_target ===
        :guarded_experimental_scalar_gmfrm_fit_entrypoint
    @test gmfrm_experimental_decision.prior_likelihood_sensitivity_grid_interpretation.interpretation ===
        :guarded_scalar_gmfrm_prior_likelihood_sensitivity_grid_passed
    @test gmfrm_experimental_decision.prior_likelihood_sensitivity_grid_interpretation.public_exposure_support ===
        :satisfied_by_real_data_case_study
    @test gmfrm_experimental_decision.prior_likelihood_sensitivity_grid_interpretation.required_followup ===
        :claim_level_recovery_and_reproduction_archive
    @test gmfrm_experimental_decision.real_data_case_study_interpretation.status ===
        :case_study_recorded
    @test gmfrm_experimental_decision.real_data_case_study_interpretation.review_target ===
        :guarded_experimental_scalar_gmfrm_fit_entrypoint
    @test gmfrm_experimental_decision.real_data_case_study_interpretation.interpretation ===
        :guarded_scalar_gmfrm_real_data_case_study_passed
    @test gmfrm_experimental_decision.real_data_case_study_interpretation.public_exposure_support ===
        :satisfied_by_claim_recovery_reproduction_archive
    @test gmfrm_experimental_decision.real_data_case_study_interpretation.required_followup ===
        :broader_experimental_exposure_decision_review
    @test gmfrm_experimental_decision.claim_recovery_reproduction_archive_interpretation.status ===
        :archive_recorded
    @test gmfrm_experimental_decision.claim_recovery_reproduction_archive_interpretation.review_target ===
        :guarded_experimental_scalar_gmfrm_claim_support
    @test gmfrm_experimental_decision.claim_recovery_reproduction_archive_interpretation.interpretation ===
        :claim_level_recovery_reproduction_archive_recorded
    @test gmfrm_experimental_decision.claim_recovery_reproduction_archive_interpretation.public_exposure_support ===
        :satisfied_by_broader_experimental_exposure_decision_review
    @test gmfrm_experimental_decision.claim_recovery_reproduction_archive_interpretation.required_followup ===
        :satisfied_by_broader_experimental_exposure_decision_review
    @test gmfrm_experimental_decision.broader_experimental_exposure_decision_review_interpretation.status ===
        :decision_recorded
    @test gmfrm_experimental_decision.broader_experimental_exposure_decision_review_interpretation.review_target ===
        :broader_generalized_model_exposure
    @test gmfrm_experimental_decision.broader_experimental_exposure_decision_review_interpretation.interpretation ===
        :broader_exposure_review_recorded_full_archive_available_keep_broader_claims_blocked
    @test gmfrm_experimental_decision.broader_experimental_exposure_decision_review_interpretation.public_exposure_support ===
        :guarded_scalar_gmfrm_only
    @test gmfrm_experimental_decision.broader_experimental_exposure_decision_review_interpretation.required_followup ===
        :manual_publication_or_registration_by_user_only
    @test gmfrm_experimental_decision.mgmfrm_baseline_comparison_interpretation.status ===
        :comparison_recorded
    @test gmfrm_experimental_decision.mgmfrm_baseline_comparison_interpretation.comparison_target ===
        :confirmatory_mgmfrm_same_observation_waic_against_mfrm_baselines
    @test gmfrm_experimental_decision.mgmfrm_baseline_comparison_interpretation.interpretation ===
        :baseline_comparison_recorded_keep_mgmfrm_internal
    @test gmfrm_experimental_decision.mgmfrm_baseline_comparison_interpretation.public_exposure_support ===
        :insufficient_for_mgmfrm_public_fit
    @test gmfrm_experimental_decision.mgmfrm_baseline_comparison_interpretation.required_followup ===
        :manual_public_scope_review_for_mgmfrm_fit
    @test gmfrm_experimental_decision.mgmfrm_sparse_recovery_grid_interpretation.status ===
        :grid_recorded
    @test gmfrm_experimental_decision.mgmfrm_sparse_recovery_grid_interpretation.review_target ===
        :confirmatory_mgmfrm_sparse_connected_recovery
    @test gmfrm_experimental_decision.mgmfrm_sparse_recovery_grid_interpretation.interpretation ===
        :sparse_recovery_grid_recorded_keep_mgmfrm_internal
    @test gmfrm_experimental_decision.mgmfrm_sparse_recovery_grid_interpretation.public_exposure_support ===
        :insufficient_for_broader_public_claims
    @test gmfrm_experimental_decision.mgmfrm_sparse_recovery_grid_interpretation.required_followup ===
        :manual_public_scope_review_for_mgmfrm_fit
    @test gmfrm_experimental_decision.dff_estimand_validation_grid_interpretation.status ===
        :grid_recorded
    @test gmfrm_experimental_decision.dff_estimand_validation_grid_interpretation.review_target ===
        :dff_estimand_validation_evidence
    @test gmfrm_experimental_decision.dff_estimand_validation_grid_interpretation.interpretation ===
        :dff_estimands_predeclared_keep_model_effects_validation_only
    @test gmfrm_experimental_decision.dff_estimand_validation_grid_interpretation.public_exposure_support ===
        :satisfied_for_gate_e_followup_without_dff_model_effect_fit
    @test gmfrm_experimental_decision.dff_estimand_validation_grid_interpretation.required_followup ===
        :future_dff_model_effect_fit_policy
    @test gmfrm_experimental_decision.manuscript_scale_simulation_grid_interpretation.status ===
        :grid_recorded
    @test gmfrm_experimental_decision.manuscript_scale_simulation_grid_interpretation.review_target ===
        :gate_e_broader_generalized_claim_evidence
    @test gmfrm_experimental_decision.manuscript_scale_simulation_grid_interpretation.interpretation ===
        :manuscript_scale_grid_recorded_full_archive_available
    @test gmfrm_experimental_decision.manuscript_scale_simulation_grid_interpretation.public_exposure_support ===
        :full_archive_recorded_without_broader_fit
    @test gmfrm_experimental_decision.manuscript_scale_simulation_grid_interpretation.required_followup ===
        :manual_publication_or_registration_by_user_only
    @test gmfrm_experimental_decision.full_paper_reproduction_archive_interpretation.status ===
        :archive_recorded
    @test gmfrm_experimental_decision.full_paper_reproduction_archive_interpretation.review_target ===
        :full_local_reproduction_bundle
    @test gmfrm_experimental_decision.full_paper_reproduction_archive_interpretation.interpretation ===
        :full_archive_recorded_without_publication_or_registration
    @test gmfrm_experimental_decision.full_paper_reproduction_archive_interpretation.public_exposure_support ===
        :local_full_reproduction_archive_recorded
    @test gmfrm_experimental_decision.full_paper_reproduction_archive_interpretation.required_followup ===
        :manual_publication_or_registration_by_user_only
    @test gmfrm_experimental_decision.caveat_docs_artifact ==
        "docs/src/fitting.md#guarded-generalized-model-caveats"
    gmfrm_prior_policy = gmfrm_experimental_decision.prior_jacobian_policy
    @test gmfrm_prior_policy.schema ==
        "bayesianmgmfrm.generalized_raw_prior_jacobian_policy.v1"
    @test gmfrm_prior_policy.family === :gmfrm
    @test gmfrm_prior_policy.scope === :scalar_gmfrm_fit_ready_candidate
    @test gmfrm_prior_policy.status === :policy_recorded
    @test gmfrm_prior_policy.prior_policy === :independent_normal_raw_coordinates
    @test !gmfrm_prior_policy.direct_scale_priors
    @test gmfrm_prior_policy.jacobian_policy === :none_raw_coordinate_density
    gmfrm_decision_raw_prior_controls =
        gmfrm_experimental_decision.raw_prior_control_manifest
    @test gmfrm_decision_raw_prior_controls.schema ==
        "bayesianmgmfrm.generalized_raw_prior_control_manifest.v1"
    @test gmfrm_decision_raw_prior_controls.public_fit
    @test gmfrm_decision_raw_prior_controls.experimental_public
    @test any(row -> row.raw_block === :log_rater_consistency &&
        row.scale_parameter === :log_consistency_sd,
        gmfrm_decision_raw_prior_controls.rows)
    @test any(row -> row.raw_block === :log_item_discrimination_free &&
        row.scale_parameter === :log_discrimination_sd,
        gmfrm_decision_raw_prior_controls.rows)
    gmfrm_fit_artifact_contract =
        gmfrm_experimental_decision.fit_artifact_contract
    @test gmfrm_fit_artifact_contract.schema ==
        "bayesianmgmfrm.experimental_generalized_fit_artifact_contract.v1"
    @test gmfrm_fit_artifact_contract.family === :gmfrm
    @test gmfrm_fit_artifact_contract.scope === :scalar_gmfrm_fit_ready_candidate
    @test gmfrm_fit_artifact_contract.status === :contract_recorded
    @test gmfrm_fit_artifact_contract.public_fit
    @test gmfrm_fit_artifact_contract.experimental_public
    @test gmfrm_fit_artifact_contract.artifact_kind ===
        :experimental_generalized_fit_artifact
    @test gmfrm_fit_artifact_contract.summary.enables_public_fit
    @test any(row -> row.field === :experimental_public &&
        row.status === :required,
        gmfrm_fit_artifact_contract.required_fields)
    @test any(row -> row.field === :public_target_label &&
        row.status === :required,
        gmfrm_fit_artifact_contract.required_fields)
    @test any(row -> row.field === :internal_target_constructor &&
        row.status === :required,
        gmfrm_fit_artifact_contract.required_fields)
    @test any(row -> row.field === :parameter_layout &&
        row.status === :required,
        gmfrm_fit_artifact_contract.required_fields)
    @test any(row -> row.field === :raw_prior_control_manifest &&
        row.status === :required,
        gmfrm_fit_artifact_contract.required_fields)
    @test any(row -> row.field === :direct_posterior_row_schema &&
        row.status === :required,
        gmfrm_fit_artifact_contract.required_fields)
    @test any(row -> row.field === :fixture_provenance &&
        row.status === :required,
        gmfrm_fit_artifact_contract.required_fields)
    @test any(row -> row.artifact === :candidate_chain_study &&
        row.value == "test/fixtures/gmfrm_candidate_chain_study.json",
        gmfrm_fit_artifact_contract.provenance_rows)
    @test any(row -> row.option === :family &&
        row.value === :gmfrm &&
        row.status === :candidate_only,
        gmfrm_experimental_decision.accepted_candidate_options)
    @test any(row -> row.option === :entrypoint &&
        row.value == "BayesianMGMFRM.Experimental.fit(spec)" &&
        row.status === :enabled_guarded,
        gmfrm_experimental_decision.accepted_candidate_options)
    @test any(row -> row.option === :legacy_entrypoint &&
        row.value == "BayesianMGMFRM.fit(spec; experimental = true)" &&
        row.status === :compatibility_only,
        gmfrm_experimental_decision.accepted_candidate_options)
    @test any(row -> row.option === :rater_steps &&
        row.value === :internal_source_block &&
        row.status === :candidate_only &&
        row.note === :not_a_public_fit_option,
        gmfrm_experimental_decision.accepted_candidate_options)
    @test any(row -> row.option === :family &&
        row.value === :mgmfrm &&
        row.status === :blocked,
        gmfrm_experimental_decision.rejected_public_options)
    @test any(row -> row.option === :discrimination &&
        row.value === :item &&
        row.status === :blocked &&
        row.blocker === :item_discrimination_promotion_target_not_selected,
        gmfrm_experimental_decision.rejected_public_options)
    @test any(row -> row.option === :rater_steps &&
        row.value === :public_option &&
        row.status === :blocked &&
        row.blocker === :rater_step_public_option_policy_not_promoted,
        gmfrm_experimental_decision.rejected_public_options)
    @test any(row -> row.option === :bias_or_dff_terms &&
        row.value === :model_effects &&
        row.status === :blocked &&
        row.blocker === :dff_model_effect_fit_policy_not_promoted,
        gmfrm_experimental_decision.rejected_public_options)
    @test any(row -> row.evidence === :candidate_chain_study &&
        row.status === :done,
        gmfrm_experimental_decision.evidence_rows)
    @test any(row -> row.evidence === :recovery_smoke_study &&
        row.status === :done,
        gmfrm_experimental_decision.evidence_rows)
    @test any(row -> row.evidence === :fit_artifact_manifest_for_experimental_public &&
        row.status === :done &&
        row.artifact === :experimental_public_fit_artifact_contract,
        gmfrm_experimental_decision.evidence_rows)
    @test any(row -> row.evidence === :item_discrimination_promotion_decision &&
        row.status === :done &&
        row.artifact === :gmfrm_item_discrimination_promotion_decision,
        gmfrm_experimental_decision.evidence_rows)
    @test any(row -> row.evidence === :stress_chain_grid &&
        row.status === :done &&
        row.artifact == "test/fixtures/gmfrm_stress_chain_grid.json",
        gmfrm_experimental_decision.evidence_rows)
    @test any(row -> row.evidence === :baseline_comparison &&
        row.status === :done &&
        row.artifact == "test/fixtures/gmfrm_baseline_comparison.json",
        gmfrm_experimental_decision.evidence_rows)
    @test any(row -> row.evidence === :baseline_calibration_grid &&
        row.status === :done &&
        row.artifact == "test/fixtures/gmfrm_baseline_calibration_grid.json",
        gmfrm_experimental_decision.evidence_rows)
    @test any(row -> row.evidence === :interval_decision_grid &&
        row.status === :done &&
        row.artifact == "test/fixtures/gmfrm_interval_decision_grid.json",
        gmfrm_experimental_decision.evidence_rows)
    @test any(row -> row.evidence === :sparse_design_grid &&
        row.status === :done &&
        row.artifact == "test/fixtures/gmfrm_sparse_design_grid.json",
        gmfrm_experimental_decision.evidence_rows)
    @test any(row -> row.evidence === :waic_influence_review &&
        row.status === :done &&
        row.artifact == "test/fixtures/gmfrm_waic_influence_review.json",
        gmfrm_experimental_decision.evidence_rows)
    @test any(row -> row.evidence === :psis_loo_review &&
        row.status === :done &&
        row.artifact == "test/fixtures/gmfrm_psis_loo_review.json",
        gmfrm_experimental_decision.evidence_rows)
    @test any(row -> row.evidence === :exact_loo_or_kfold_review &&
        row.status === :done &&
        row.artifact == "test/fixtures/gmfrm_exact_loo_or_kfold_review.json",
        gmfrm_experimental_decision.evidence_rows)
    @test any(row -> row.evidence === :guarded_exposure_review &&
        row.status === :done &&
        row.artifact == "test/fixtures/gmfrm_guarded_exposure_review.json",
        gmfrm_experimental_decision.evidence_rows)
    @test any(row -> row.evidence === :guarded_fit_api_dry_run &&
        row.status === :done &&
        row.artifact == "test/fixtures/gmfrm_guarded_fit_api_dry_run.json",
        gmfrm_experimental_decision.evidence_rows)
    @test any(row -> row.evidence === :guarded_fit_method_wiring &&
        row.status === :done &&
        row.artifact == "test/fixtures/gmfrm_guarded_fit_method_wiring.json",
        gmfrm_experimental_decision.evidence_rows)
    @test any(row -> row.evidence === :experimental_fit_validation_grid &&
        row.status === :done &&
        row.artifact == "test/fixtures/gmfrm_experimental_fit_validation_grid.json",
        gmfrm_experimental_decision.evidence_rows)
    @test any(row -> row.evidence === :posterior_predictive_grid &&
        row.status === :done &&
        row.artifact == "test/fixtures/gmfrm_posterior_predictive_grid.json",
        gmfrm_experimental_decision.evidence_rows)
    @test any(row -> row.evidence === :sparse_pathology_recovery_grid &&
        row.status === :done &&
        row.artifact == "test/fixtures/gmfrm_sparse_pathology_recovery_grid.json",
        gmfrm_experimental_decision.evidence_rows)
    @test any(row -> row.evidence === :prior_likelihood_sensitivity_grid &&
        row.status === :done &&
        row.artifact == "test/fixtures/gmfrm_prior_likelihood_sensitivity_grid.json",
        gmfrm_experimental_decision.evidence_rows)
    @test any(row -> row.evidence === :real_data_case_study &&
        row.status === :done &&
        row.artifact == "test/fixtures/gmfrm_real_data_case_study.json",
        gmfrm_experimental_decision.evidence_rows)
    @test any(row -> row.evidence === :claim_recovery_reproduction_archive &&
        row.status === :done &&
        row.artifact ==
            "test/fixtures/gmfrm_claim_recovery_reproduction_archive.json",
        gmfrm_experimental_decision.evidence_rows)
    @test any(row -> row.evidence === :broader_experimental_exposure_decision_review &&
        row.status === :done &&
        row.artifact ==
            "test/fixtures/gmfrm_broader_experimental_exposure_decision_review.json",
        gmfrm_experimental_decision.evidence_rows)
    @test any(row -> row.evidence === :mgmfrm_baseline_comparison &&
        row.status === :done &&
        row.artifact == "test/fixtures/mgmfrm_baseline_comparison.json",
        gmfrm_experimental_decision.evidence_rows)
    @test any(row -> row.evidence === :mgmfrm_sparse_recovery_grid &&
        row.status === :done &&
        row.artifact == "test/fixtures/mgmfrm_sparse_recovery_grid.json",
        gmfrm_experimental_decision.evidence_rows)
    @test any(row -> row.evidence === :dff_estimand_validation_grid &&
        row.status === :done &&
        row.artifact == "test/fixtures/gmfrm_dff_estimand_validation_grid.json",
        gmfrm_experimental_decision.evidence_rows)
    @test any(row -> row.evidence === :manuscript_scale_simulation_grid &&
        row.status === :done &&
        row.artifact ==
            "test/fixtures/gmfrm_manuscript_scale_simulation_grid.json",
        gmfrm_experimental_decision.evidence_rows)
    @test any(row -> row.evidence === :full_paper_reproduction_archive &&
        row.status === :done &&
        row.artifact ==
            "test/fixtures/gmfrm_full_paper_reproduction_archive.json",
        gmfrm_experimental_decision.evidence_rows)
    @test any(row -> row.evidence === :direct_prior_jacobian_policy &&
        row.status === :done &&
        row.artifact === :generalized_raw_prior_jacobian_policy,
        gmfrm_experimental_decision.evidence_rows)
    @test any(row -> row.evidence === :raw_prior_control_manifest &&
        row.status === :done &&
        row.artifact === :generalized_raw_prior_control_manifest,
        gmfrm_experimental_decision.evidence_rows)
    @test any(row -> row.evidence === :public_caveat_docs &&
        row.status === :done &&
        row.artifact == "docs/src/fitting.md#guarded-generalized-model-caveats",
        gmfrm_experimental_decision.evidence_rows)
    @test !any(row -> row.blocker === :stress_chain_grid_missing,
        gmfrm_experimental_decision.blocker_rows)
    @test !any(row -> row.blocker === :baseline_comparison_missing,
        gmfrm_experimental_decision.blocker_rows)
    @test !any(row -> row.blocker === :baseline_calibration_grid_missing,
        gmfrm_experimental_decision.blocker_rows)
    @test !any(row -> row.blocker === :interval_coverage_grid_missing,
        gmfrm_experimental_decision.blocker_rows)
    @test !any(row -> row.blocker === :decision_stability_grid_missing,
        gmfrm_experimental_decision.blocker_rows)
    @test !any(row -> row.blocker === :guarded_exposure_review_missing,
        gmfrm_experimental_decision.blocker_rows)
    @test !any(row -> row.blocker === :high_variance_waic_requires_followup,
        gmfrm_experimental_decision.blocker_rows)
    @test !any(row -> row.blocker === :high_variance_waic_requires_psis_loo_followup,
        gmfrm_experimental_decision.blocker_rows)
    @test !any(row -> row.blocker === :high_pareto_k_requires_exact_loo_or_kfold_followup,
        gmfrm_experimental_decision.blocker_rows)
    @test !any(row -> row.blocker === :guarded_fit_api_dry_run_missing,
        gmfrm_experimental_decision.blocker_rows)
    @test !any(row -> row.blocker === :guarded_fit_method_wiring_missing,
        gmfrm_experimental_decision.blocker_rows)
    @test !any(row -> row.blocker === :experimental_fit_validation_grid_missing,
        gmfrm_experimental_decision.blocker_rows)
    @test !any(row -> row.blocker === :scalar_gmfrm_posterior_predictive_grid_missing,
        gmfrm_experimental_decision.blocker_rows)
    @test !any(row -> row.blocker === :scalar_gmfrm_sparse_pathology_recovery_grid_missing,
        gmfrm_experimental_decision.blocker_rows)
    @test !any(row -> row.blocker === :scalar_gmfrm_prior_likelihood_sensitivity_grid_missing,
        gmfrm_experimental_decision.blocker_rows)
    @test !any(row -> row.blocker === :scalar_gmfrm_real_data_case_study_missing,
        gmfrm_experimental_decision.blocker_rows)
    @test !any(row -> row.blocker === :claim_level_recovery_and_reproduction_archive_missing,
        gmfrm_experimental_decision.blocker_rows)
    @test !any(row -> row.blocker === :broader_experimental_exposure_decision_review_missing,
        gmfrm_experimental_decision.blocker_rows)
    @test !any(row -> row.blocker === :mgmfrm_baseline_comparison_missing,
        gmfrm_experimental_decision.blocker_rows)
    @test !any(row -> row.blocker === :sparse_recovery_grid_missing,
        gmfrm_experimental_decision.blocker_rows)
    @test !any(row -> row.blocker === :dff_estimand_and_validation_evidence_missing,
        gmfrm_experimental_decision.blocker_rows)
    @test !any(row -> row.blocker === :manuscript_scale_simulation_grid_missing,
        gmfrm_experimental_decision.blocker_rows)
    @test !any(row -> row.blocker === :full_paper_reproduction_archive_missing,
        gmfrm_experimental_decision.blocker_rows)
    @test !any(row -> row.blocker === :sparse_design_grid_missing,
        gmfrm_experimental_decision.blocker_rows)
    @test !any(row -> row.blocker === :direct_prior_jacobian_policy_pending,
        gmfrm_experimental_decision.blocker_rows)
    @test !any(row -> row.blocker === :public_fit_artifact_contract_missing,
        gmfrm_experimental_decision.blocker_rows)
    @test !any(row -> row.blocker === :public_caveat_docs_missing,
        gmfrm_experimental_decision.blocker_rows)
    @test gmfrm_experimental_decision.summary.fit_allowed
    @test gmfrm_experimental_decision.summary.canonical_namespace_enabled
    @test gmfrm_experimental_decision.summary.experimental_keyword_enabled
    @test gmfrm_experimental_decision.summary.legacy_keyword_status ===
        :compatibility_only
    @test gmfrm_experimental_decision.summary.n_evidence_done >= 28
    @test gmfrm_experimental_decision.summary.n_evidence_pending == 0
    @test gmfrm_experimental_decision.summary.n_blockers == 0
    @test gmfrm_experimental_decision.summary.next_gate ===
        :manual_publication_or_registration_by_user_only
    gmfrm_raw_params = [
        0.3, -0.2,
        0.1, -0.05,
        -0.2,
        log(2.0),
        log(1.2), log(0.8),
        0.25, -0.1,
    ]
    @test BayesianMGMFRM._gmfrm_source_constrained_params_from_unconstrained(
        gmfrm_preview,
        gmfrm_raw_params,
    ) ≈ gmfrm_params
    gmfrm_transform_diagnostics =
        BayesianMGMFRM._gmfrm_promotion_candidate_transform_diagnostics(
            gmfrm_preview,
            gmfrm_raw_params,
        )
    @test gmfrm_transform_diagnostics.schema ==
        "bayesianmgmfrm.gmfrm_promotion_candidate_transform_diagnostics.v1"
    @test gmfrm_transform_diagnostics.summary.passed
    @test gmfrm_transform_diagnostics.summary.flag === :ok
    @test gmfrm_transform_diagnostics.summary.n_raw_parameters == gmfrm_raw_blueprint.n_parameters
    @test gmfrm_transform_diagnostics.summary.n_direct_parameters == length(gmfrm_params)
    @test gmfrm_transform_diagnostics.direct_parameter_names == gmfrm_preview.parameter_names
    @test gmfrm_transform_diagnostics.direct_parameter_values ≈ gmfrm_params
    @test gmfrm_transform_diagnostics.raw_parameter_values ≈ gmfrm_raw_params
    @test gmfrm_transform_diagnostics.raw_pointwise_loglikelihood ≈
        gmfrm_transform_diagnostics.direct_pointwise_loglikelihood
    @test gmfrm_transform_diagnostics.summary.max_pointwise_abs_error <= 1e-10
    @test all(row -> row.passed, gmfrm_transform_diagnostics.constraint_rows)
    gmfrm_transform_item_block = only(filter(row -> row.block === :item,
        gmfrm_transform_diagnostics.direct_blocks))
    @test gmfrm_transform_item_block.values ≈ [-0.2, 0.2]
    gmfrm_transform_discrimination_block = only(filter(row -> row.block === :item_discrimination,
        gmfrm_transform_diagnostics.direct_blocks))
    @test gmfrm_transform_discrimination_block.values ≈ [2.0, 0.5]
    @test_throws ArgumentError BayesianMGMFRM._gmfrm_source_constrained_params_from_unconstrained(
        gmfrm_preview,
        gmfrm_raw_params[1:end-1],
    )
    for block in (:log_item_discrimination_free, :log_rater_consistency),
            boundary_value in (800.0, -1000.0)
        boundary_raw_params = copy(gmfrm_raw_params)
        boundary_raw_params[first(gmfrm_raw_blueprint.blocks[block])] = boundary_value
        @test_throws ArgumentError BayesianMGMFRM._gmfrm_source_constrained_params_from_unconstrained(
            gmfrm_preview,
            boundary_raw_params,
        )
    end
    gmfrm_source_values = BayesianMGMFRM._gmfrm_source_fixture_values(gmfrm_preview, gmfrm_params)
    gmfrm_source_pointwise =
        BayesianMGMFRM._gmfrm_source_pointwise_loglikelihood(gmfrm_preview, gmfrm_params)
    gmfrm_direct_pointwise_fixture =
        BayesianMGMFRM._gmfrm_promotion_candidate_pointwise_fixture(gmfrm_preview, gmfrm_params)
    @test gmfrm_direct_pointwise_fixture.schema ==
        "bayesianmgmfrm.gmfrm_promotion_candidate_pointwise_fixture.v1"
    @test gmfrm_direct_pointwise_fixture.summary.passed
    @test gmfrm_direct_pointwise_fixture.summary.flag === :ok
    @test gmfrm_direct_pointwise_fixture.density_space === :constrained_direct
    @test gmfrm_direct_pointwise_fixture.parameter_layout.scope ===
        :scalar_gmfrm_fit_ready_candidate
    @test gmfrm_direct_pointwise_fixture.parameter_layout.constrained_parameter_names ==
        gmfrm_direct_pointwise_fixture.parameter_names
    @test gmfrm_direct_pointwise_fixture.parameter_names == gmfrm_preview.parameter_names
    @test gmfrm_direct_pointwise_fixture.parameter_values ≈ gmfrm_params
    @test gmfrm_direct_pointwise_fixture.summary.n_rows == length(gmfrm_predictors)
    @test gmfrm_direct_pointwise_fixture.summary.n_pointwise == identified_data.n
    @test gmfrm_direct_pointwise_fixture.pointwise_loglikelihood ≈ gmfrm_source_pointwise
    @test gmfrm_direct_pointwise_fixture.loglikelihood ≈ sum(gmfrm_source_pointwise)
    @test isequal(gmfrm_direct_pointwise_fixture.rows, gmfrm_source_values)
    @test all(row -> row.passed, gmfrm_direct_pointwise_fixture.constraint_rows)
    @test only(filter(row -> row.block === :rater_consistency,
        gmfrm_direct_pointwise_fixture.blocks)).values ≈ [1.2, 0.8]
    @test BayesianMGMFRM._gmfrm_source_pointwise_loglikelihood_from_unconstrained(
        gmfrm_preview,
        gmfrm_raw_params,
    ) ≈ gmfrm_source_pointwise
    @test BayesianMGMFRM._gmfrm_source_loglikelihood_from_unconstrained(
        gmfrm_preview,
        gmfrm_raw_params,
    ) ≈ sum(gmfrm_source_pointwise)
    @test_throws ArgumentError BayesianMGMFRM._gmfrm_source_pointwise_loglikelihood_from_unconstrained(
        gmfrm_preview,
        gmfrm_raw_params[1:end-1],
    )
    source_prior = BayesianMGMFRM._SourceFixturePrior(;
        person_sd = 1.1,
        rater_sd = 1.2,
        item_sd = 1.3,
        log_discrimination_sd = 1.4,
        log_consistency_sd = 1.5,
        step_sd = 1.6,
    )
    gmfrm_target = BayesianMGMFRM._source_fixture_logdensity(gmfrm_preview; prior = source_prior)
    gmfrm_spec_target = BayesianMGMFRM._source_fixture_logdensity(gmfrm_spec; prior = source_prior)
    gmfrm_candidate =
        BayesianMGMFRM._gmfrm_promotion_candidate_logdensity(gmfrm_preview; prior = source_prior)
    gmfrm_spec_candidate =
        BayesianMGMFRM._gmfrm_promotion_candidate_logdensity(gmfrm_spec; prior = source_prior)
    @test LogDensityProblems.dimension(gmfrm_target) == gmfrm_raw_blueprint.n_parameters
    @test LogDensityProblems.dimension(gmfrm_spec_target) == gmfrm_raw_blueprint.n_parameters
    @test LogDensityProblems.dimension(gmfrm_candidate) == gmfrm_raw_blueprint.n_parameters
    @test LogDensityProblems.dimension(gmfrm_spec_candidate) == gmfrm_raw_blueprint.n_parameters
    @test gmfrm_target.blueprint.status === :internal_source_fixture
    @test gmfrm_candidate.blueprint.status === :internal_fit_ready_candidate
    @test gmfrm_candidate.blueprint.scope === :scalar_gmfrm_fit_ready_candidate
    @test gmfrm_candidate.blueprint.parameter_names == gmfrm_raw_blueprint.parameter_names
    @test LogDensityProblems.capabilities(typeof(gmfrm_target)) == LogDensityProblems.LogDensityOrder{0}()
    @test LogDensityProblems.capabilities(typeof(gmfrm_candidate)) == LogDensityProblems.LogDensityOrder{0}()
    @test initial_params(gmfrm_target; value = 0.05) == fill(0.05, gmfrm_raw_blueprint.n_parameters)
    @test initial_params(gmfrm_candidate; value = 0.05) == fill(0.05, gmfrm_raw_blueprint.n_parameters)
    @test occursin("SourceFixtureLogDensity(gmfrm", sprint(show, gmfrm_target))
    @test occursin("GMFRMPromotionCandidateLogDensity", sprint(show, gmfrm_candidate))
    gmfrm_prior_sds = [
        1.1, 1.1,
        1.2, 1.2,
        1.3,
        1.4,
        1.5, 1.5,
        1.6, 1.6,
    ]
    gmfrm_expected_prior = sum(test_normal_logpdf(x, sd)
        for (x, sd) in zip(gmfrm_raw_params, gmfrm_prior_sds))
    @test BayesianMGMFRM._source_fixture_logprior(gmfrm_target, gmfrm_raw_params) ≈
        gmfrm_expected_prior
    @test BayesianMGMFRM._source_fixture_loglikelihood(gmfrm_target, gmfrm_raw_params) ≈
        sum(gmfrm_source_pointwise)
    @test LogDensityProblems.logdensity(gmfrm_target, gmfrm_raw_params) ≈
        sum(gmfrm_source_pointwise) + gmfrm_expected_prior
    @test LogDensityProblems.logdensity(gmfrm_spec_target, gmfrm_raw_params) ≈
        LogDensityProblems.logdensity(gmfrm_target, gmfrm_raw_params)
    @test LogDensityProblems.logdensity(gmfrm_candidate, gmfrm_raw_params) ≈
        LogDensityProblems.logdensity(gmfrm_target, gmfrm_raw_params)
    @test LogDensityProblems.logdensity(gmfrm_spec_candidate, gmfrm_raw_params) ≈
        LogDensityProblems.logdensity(gmfrm_candidate, gmfrm_raw_params)
    gmfrm_raw_pointwise_fixture =
        BayesianMGMFRM._gmfrm_promotion_candidate_pointwise_fixture(
            gmfrm_candidate,
            gmfrm_raw_params,
        )
    @test gmfrm_raw_pointwise_fixture.summary.passed
    @test gmfrm_raw_pointwise_fixture.raw_parameter_names == gmfrm_raw_blueprint.parameter_names
    @test gmfrm_raw_pointwise_fixture.parameter_layout.raw_parameter_names ==
        gmfrm_raw_pointwise_fixture.raw_parameter_names
    @test gmfrm_raw_pointwise_fixture.raw_parameter_values ≈ gmfrm_raw_params
    @test gmfrm_raw_pointwise_fixture.parameter_values ≈ gmfrm_params
    @test gmfrm_raw_pointwise_fixture.pointwise_loglikelihood ≈ gmfrm_source_pointwise
    gmfrm_logp = x -> LogDensityProblems.logdensity(gmfrm_target, x)
    gmfrm_forward_gradient = check_forwarddiff_gradient(gmfrm_logp, gmfrm_raw_params)
    @test length(gmfrm_forward_gradient) == gmfrm_raw_blueprint.n_parameters
    gmfrm_candidate_diagnostics = BayesianMGMFRM._gmfrm_promotion_candidate_diagnostics(
        gmfrm_candidate,
        gmfrm_raw_params;
        finite_difference_coords = [1, first(gmfrm_raw_blueprint.blocks[:log_item_discrimination_free])],
    )
    @test gmfrm_candidate_diagnostics.schema ==
        "bayesianmgmfrm.gmfrm_promotion_candidate_diagnostics.v1"
    @test gmfrm_candidate_diagnostics.summary.passed
    @test gmfrm_candidate_diagnostics.summary.flag === :ok
    @test gmfrm_candidate_diagnostics.summary.n_checked == 2
    @test gmfrm_candidate_diagnostics.summary.n_failed == 0
    @test gmfrm_candidate_diagnostics.summary.finite_logdensity
    @test gmfrm_candidate_diagnostics.summary.finite_gradient
    @test length(gmfrm_candidate_diagnostics.gradient) == gmfrm_raw_blueprint.n_parameters
    @test all(row -> row.passed, gmfrm_candidate_diagnostics.finite_difference_rows)
    @test BayesianMGMFRM._gmfrm_promotion_candidate_diagnostics(
        gmfrm_spec,
        gmfrm_raw_params;
        prior = source_prior,
        finite_difference_coords = [1],
    ).summary.passed
    gmfrm_hmc_samples, gmfrm_hmc_stats = check_advancedhmc_smoke(
        gmfrm_target,
        gmfrm_raw_params;
        seed = 20260619,
    )
    @test length(gmfrm_hmc_samples) == length(gmfrm_hmc_stats) == 2
    gmfrm_sampler_diagnostics =
        BayesianMGMFRM._gmfrm_promotion_candidate_sampler_diagnostics(
            gmfrm_candidate,
            gmfrm_raw_params;
            seed = 20260620,
            ndraws = 4,
            warmup = 2,
            chains = 2,
            step_size = 0.02,
            max_depth = 3,
            metric = :unit,
            rhat_threshold = 100.0,
            ess_threshold = 1.0,
        )
    @test gmfrm_sampler_diagnostics.schema ==
        "bayesianmgmfrm.gmfrm_promotion_candidate_sampler_diagnostics.v1"
    @test gmfrm_sampler_diagnostics.status === :internal_promotion_candidate
    @test gmfrm_sampler_diagnostics.public_fit === false
    @test gmfrm_sampler_diagnostics.fit_ready === false
    @test gmfrm_sampler_diagnostics.backend === :advancedhmc
    @test gmfrm_sampler_diagnostics.sampler === :nuts
    @test gmfrm_sampler_diagnostics.density_space === :raw_unconstrained
    @test gmfrm_sampler_diagnostics.raw_parameter_names == gmfrm_raw_blueprint.parameter_names
    @test gmfrm_sampler_diagnostics.direct_parameter_names ==
        gmfrm_raw_blueprint.constrained_parameter_names
    @test gmfrm_sampler_diagnostics.initial_raw_parameter_values ≈ gmfrm_raw_params
    @test gmfrm_sampler_diagnostics.initial_direct_parameter_values ≈ gmfrm_params
    @test isfinite(gmfrm_sampler_diagnostics.initial_logdensity)
    @test size(gmfrm_sampler_diagnostics.draws) ==
        (8, gmfrm_raw_blueprint.n_parameters)
    @test size(gmfrm_sampler_diagnostics.direct_draws) == (8, length(gmfrm_params))
    @test size(gmfrm_sampler_diagnostics.direct_pointwise_loglikelihood) ==
        (8, identified_data.n)
    @test length(gmfrm_sampler_diagnostics.direct_loglikelihood) == 8
    @test length(gmfrm_sampler_diagnostics.logdensity) == 8
    @test length(gmfrm_sampler_diagnostics.chain_ids) == 8
    @test length(gmfrm_sampler_diagnostics.iterations) == 8
    @test all(isfinite, gmfrm_sampler_diagnostics.draws)
    @test all(isfinite, gmfrm_sampler_diagnostics.direct_draws)
    @test all(isfinite, gmfrm_sampler_diagnostics.direct_pointwise_loglikelihood)
    @test all(isfinite, gmfrm_sampler_diagnostics.direct_loglikelihood)
    @test all(isfinite, gmfrm_sampler_diagnostics.logdensity)
    @test length(gmfrm_sampler_diagnostics.chain_acceptance_rate) == 2
    @test length(gmfrm_sampler_diagnostics.sampler_stats) == 8
    @test all(row -> row.chain in (1, 2), gmfrm_sampler_diagnostics.sampler_stats)
    @test all(row -> 1 <= row.iteration <= 4, gmfrm_sampler_diagnostics.sampler_stats)
    @test all(row -> isfinite(row.log_density), gmfrm_sampler_diagnostics.sampler_stats)
    @test length(gmfrm_sampler_diagnostics.sampler_rows) == 2
    @test all(row -> row.backend === :advancedhmc,
        gmfrm_sampler_diagnostics.sampler_rows)
    @test all(row -> row.sampler === :nuts,
        gmfrm_sampler_diagnostics.sampler_rows)
    @test all(row -> row.n_draws == 4,
        gmfrm_sampler_diagnostics.sampler_rows)
    @test all(row -> row.n_finite_logdensity == 4,
        gmfrm_sampler_diagnostics.sampler_rows)
    @test all(row -> row.n_nonfinite_logdensity == 0,
        gmfrm_sampler_diagnostics.sampler_rows)
    @test length(gmfrm_sampler_diagnostics.parameter_rows) ==
        gmfrm_raw_blueprint.n_parameters
    @test [row.parameter for row in gmfrm_sampler_diagnostics.parameter_rows] ==
        gmfrm_raw_blueprint.parameter_names
    @test all(row -> row.n_chains == 2,
        gmfrm_sampler_diagnostics.parameter_rows)
    @test all(row -> row.draws_per_chain == 4,
        gmfrm_sampler_diagnostics.parameter_rows)
    @test all(row -> row.total_draws == 8,
        gmfrm_sampler_diagnostics.parameter_rows)
    @test length(gmfrm_sampler_diagnostics.block_rows) ==
        length(keys(gmfrm_raw_blueprint.blocks))
    @test any(row -> row.block === :log_item_discrimination_free &&
        row.parameter_names == ["raw_log_item_discrimination[I1]"],
        gmfrm_sampler_diagnostics.block_rows)
    @test all(row -> row.passed, gmfrm_sampler_diagnostics.direct_constraint_rows)
    @test length(gmfrm_sampler_diagnostics.direct_parameter_rows) == length(gmfrm_params)
    @test [row.parameter for row in gmfrm_sampler_diagnostics.direct_parameter_rows] ==
        gmfrm_preview.parameter_names
    @test any(row -> row.block === :item_discrimination &&
        row.parameter_names == [
            "item_discrimination[item=I1]",
            "item_discrimination[item=I2]",
        ], gmfrm_sampler_diagnostics.direct_block_rows)
    @test gmfrm_sampler_diagnostics.summary.n_chains == 2
    @test gmfrm_sampler_diagnostics.summary.draws_per_chain == 4
    @test gmfrm_sampler_diagnostics.summary.total_draws == 8
    @test gmfrm_sampler_diagnostics.summary.n_parameters ==
        gmfrm_raw_blueprint.n_parameters
    @test gmfrm_sampler_diagnostics.summary.n_direct_parameters == length(gmfrm_params)
    @test gmfrm_sampler_diagnostics.summary.n_nonfinite_logdensity == 0
    @test gmfrm_sampler_diagnostics.summary.n_nonfinite_direct_loglikelihood == 0
    @test gmfrm_sampler_diagnostics.summary.n_failed_direct_constraints == 0
    @test gmfrm_sampler_diagnostics.summary.n_divergences >= 0
    @test gmfrm_sampler_diagnostics.summary.n_max_treedepth >= 0
    @test gmfrm_sampler_diagnostics.summary.flag in
        (:ok, :direct_transform_warning, :sampler_warning, :mcmc_warning,
            :insufficient_chains, :insufficient_draws)
    @test BayesianMGMFRM._gmfrm_promotion_candidate_sampler_diagnostics(
        gmfrm_spec,
        gmfrm_raw_params;
        prior = source_prior,
        seed = 20260621,
        ndraws = 1,
        warmup = 0,
        chains = 1,
        metric = :unit,
    ).summary.n_chains == 1
    gmfrm_candidate_chain_study_fixture = optional_fixture_path("MFRM_GMFRM_CANDIDATE_CHAIN_STUDY_FIXTURE", joinpath("test", "fixtures", "gmfrm_candidate_chain_study.json"))
    if !isempty(gmfrm_candidate_chain_study_fixture)
        check_gmfrm_candidate_chain_study_fixture(
            gmfrm_candidate_chain_study_fixture,
            gmfrm_candidate,
            gmfrm_raw_params,
        )
    end
    gmfrm_stress_chain_grid_fixture = optional_fixture_path("MFRM_GMFRM_STRESS_CHAIN_GRID_FIXTURE", joinpath("test", "fixtures", "gmfrm_stress_chain_grid.json"))
    if !isempty(gmfrm_stress_chain_grid_fixture)
        check_gmfrm_stress_chain_grid_fixture(
            gmfrm_stress_chain_grid_fixture,
            gmfrm_candidate,
            gmfrm_raw_params,
        )
    end
    gmfrm_recovery_smoke_fixture = optional_fixture_path("MFRM_GMFRM_RECOVERY_SMOKE_FIXTURE", joinpath("test", "fixtures", "gmfrm_recovery_smoke.json"))
    if !isempty(gmfrm_recovery_smoke_fixture)
        check_gmfrm_recovery_smoke_fixture(gmfrm_recovery_smoke_fixture)
    end
    gmfrm_baseline_comparison_fixture = optional_fixture_path("MFRM_GMFRM_BASELINE_COMPARISON_FIXTURE", joinpath("test", "fixtures", "gmfrm_baseline_comparison.json"))
    if !isempty(gmfrm_baseline_comparison_fixture)
        check_gmfrm_baseline_comparison_fixture(gmfrm_baseline_comparison_fixture)
    end
    gmfrm_baseline_calibration_grid_fixture = optional_fixture_path("MFRM_GMFRM_BASELINE_CALIBRATION_GRID_FIXTURE", joinpath("test", "fixtures", "gmfrm_baseline_calibration_grid.json"))
    if !isempty(gmfrm_baseline_calibration_grid_fixture)
        check_gmfrm_baseline_calibration_grid_fixture(
            gmfrm_baseline_calibration_grid_fixture,
        )
    end
    gmfrm_interval_decision_grid_fixture = optional_fixture_path("MFRM_GMFRM_INTERVAL_DECISION_GRID_FIXTURE", joinpath("test", "fixtures", "gmfrm_interval_decision_grid.json"))
    if !isempty(gmfrm_interval_decision_grid_fixture)
        check_gmfrm_interval_decision_grid_fixture(
            gmfrm_interval_decision_grid_fixture,
        )
    end
    gmfrm_sparse_design_grid_fixture = optional_fixture_path("MFRM_GMFRM_SPARSE_DESIGN_GRID_FIXTURE", joinpath("test", "fixtures", "gmfrm_sparse_design_grid.json"))
    if !isempty(gmfrm_sparse_design_grid_fixture)
        check_gmfrm_sparse_design_grid_fixture(
            gmfrm_sparse_design_grid_fixture,
        )
    end
    gmfrm_waic_influence_review_fixture = optional_fixture_path("MFRM_GMFRM_WAIC_INFLUENCE_REVIEW_FIXTURE", joinpath("test", "fixtures", "gmfrm_waic_influence_review.json"))
    if !isempty(gmfrm_waic_influence_review_fixture)
        check_gmfrm_waic_influence_review_fixture(
            gmfrm_waic_influence_review_fixture,
        )
    end
    gmfrm_psis_loo_review_fixture = optional_fixture_path("MFRM_GMFRM_PSIS_LOO_REVIEW_FIXTURE", joinpath("test", "fixtures", "gmfrm_psis_loo_review.json"))
    if !isempty(gmfrm_psis_loo_review_fixture)
        check_gmfrm_psis_loo_review_fixture(
            gmfrm_psis_loo_review_fixture,
        )
    end
    gmfrm_exact_loo_or_kfold_review_fixture = optional_fixture_path("MFRM_GMFRM_EXACT_LOO_OR_KFOLD_REVIEW_FIXTURE", joinpath("test", "fixtures", "gmfrm_exact_loo_or_kfold_review.json"))
    if !isempty(gmfrm_exact_loo_or_kfold_review_fixture)
        check_gmfrm_exact_loo_or_kfold_review_fixture(
            gmfrm_exact_loo_or_kfold_review_fixture,
        )
    end
    gmfrm_guarded_fit_api_dry_run_fixture = optional_fixture_path("MFRM_GMFRM_GUARDED_FIT_API_DRY_RUN_FIXTURE", joinpath("test", "fixtures", "gmfrm_guarded_fit_api_dry_run.json"))
    if !isempty(gmfrm_guarded_fit_api_dry_run_fixture)
        check_gmfrm_guarded_fit_api_dry_run_fixture(
            gmfrm_guarded_fit_api_dry_run_fixture,
        )
    end
    gmfrm_guarded_fit_method_wiring_fixture = optional_fixture_path("MFRM_GMFRM_GUARDED_FIT_METHOD_WIRING_FIXTURE", joinpath("test", "fixtures", "gmfrm_guarded_fit_method_wiring.json"))
    if !isempty(gmfrm_guarded_fit_method_wiring_fixture)
        check_gmfrm_guarded_fit_method_wiring_fixture(
            gmfrm_guarded_fit_method_wiring_fixture,
        )
    end
    gmfrm_experimental_fit_validation_grid_fixture = optional_fixture_path("MFRM_GMFRM_EXPERIMENTAL_FIT_VALIDATION_GRID_FIXTURE", joinpath("test", "fixtures", "gmfrm_experimental_fit_validation_grid.json"))
    if !isempty(gmfrm_experimental_fit_validation_grid_fixture)
        check_gmfrm_experimental_fit_validation_grid_fixture(
            gmfrm_experimental_fit_validation_grid_fixture,
        )
    end
    gmfrm_posterior_predictive_grid_fixture = optional_fixture_path("MFRM_GMFRM_POSTERIOR_PREDICTIVE_GRID_FIXTURE", joinpath("test", "fixtures", "gmfrm_posterior_predictive_grid.json"))
    if !isempty(gmfrm_posterior_predictive_grid_fixture)
        check_gmfrm_posterior_predictive_grid_fixture(
            gmfrm_posterior_predictive_grid_fixture,
        )
    end
    gmfrm_sparse_pathology_recovery_grid_fixture = optional_fixture_path("MFRM_GMFRM_SPARSE_PATHOLOGY_RECOVERY_GRID_FIXTURE", joinpath("test", "fixtures", "gmfrm_sparse_pathology_recovery_grid.json"))
    if !isempty(gmfrm_sparse_pathology_recovery_grid_fixture)
        check_gmfrm_sparse_pathology_recovery_grid_fixture(
            gmfrm_sparse_pathology_recovery_grid_fixture,
        )
    end
    gmfrm_prior_likelihood_sensitivity_grid_fixture = optional_fixture_path("MFRM_GMFRM_PRIOR_LIKELIHOOD_SENSITIVITY_GRID_FIXTURE", joinpath("test", "fixtures", "gmfrm_prior_likelihood_sensitivity_grid.json"))
    if !isempty(gmfrm_prior_likelihood_sensitivity_grid_fixture)
        check_gmfrm_prior_likelihood_sensitivity_grid_fixture(
            gmfrm_prior_likelihood_sensitivity_grid_fixture,
        )
    end
    gmfrm_real_data_case_study_fixture = optional_fixture_path("MFRM_GMFRM_REAL_DATA_CASE_STUDY_FIXTURE", joinpath("test", "fixtures", "gmfrm_real_data_case_study.json"))
    if !isempty(gmfrm_real_data_case_study_fixture)
        check_gmfrm_real_data_case_study_fixture(
            gmfrm_real_data_case_study_fixture,
        )
    end
    gmfrm_claim_recovery_reproduction_archive_fixture = optional_fixture_path(
        "MFRM_GMFRM_CLAIM_RECOVERY_REPRODUCTION_ARCHIVE_FIXTURE",
        joinpath("test", "fixtures", "gmfrm_claim_recovery_reproduction_archive.json"))
    if !isempty(gmfrm_claim_recovery_reproduction_archive_fixture)
        check_gmfrm_claim_recovery_reproduction_archive_fixture(
            gmfrm_claim_recovery_reproduction_archive_fixture,
        )
    end
    gmfrm_full_paper_reproduction_archive_fixture = optional_fixture_path(
        "MFRM_GMFRM_FULL_PAPER_REPRODUCTION_ARCHIVE_FIXTURE",
        joinpath("test", "fixtures", "gmfrm_full_paper_reproduction_archive.json"))
    if !isempty(gmfrm_full_paper_reproduction_archive_fixture)
        check_gmfrm_full_paper_reproduction_archive_fixture(
            gmfrm_full_paper_reproduction_archive_fixture,
        )
    end
    gmfrm_prediction_target_and_model_weight_policy_fixture = optional_fixture_path(
        "MFRM_GMFRM_PREDICTION_TARGET_AND_MODEL_WEIGHT_POLICY_FIXTURE",
        joinpath("test", "fixtures", "gmfrm_prediction_target_and_model_weight_policy.json"))
    if !isempty(gmfrm_prediction_target_and_model_weight_policy_fixture)
        check_gmfrm_prediction_target_and_model_weight_policy_fixture(
            gmfrm_prediction_target_and_model_weight_policy_fixture,
        )
    end
    gmfrm_dff_estimand_validation_grid_fixture = optional_fixture_path("MFRM_GMFRM_DFF_ESTIMAND_VALIDATION_GRID_FIXTURE", joinpath("test", "fixtures", "gmfrm_dff_estimand_validation_grid.json"))
    if !isempty(gmfrm_dff_estimand_validation_grid_fixture)
        check_gmfrm_dff_estimand_validation_grid_fixture(
            gmfrm_dff_estimand_validation_grid_fixture,
        )
    end
    gmfrm_manuscript_scale_simulation_grid_fixture = optional_fixture_path(
        "MFRM_GMFRM_MANUSCRIPT_SCALE_SIMULATION_GRID_FIXTURE",
        joinpath("test", "fixtures", "gmfrm_manuscript_scale_simulation_grid.json"))
    if !isempty(gmfrm_manuscript_scale_simulation_grid_fixture)
        check_gmfrm_manuscript_scale_simulation_grid_fixture(
            gmfrm_manuscript_scale_simulation_grid_fixture,
        )
    end
    gmfrm_broader_experimental_exposure_decision_review_fixture = optional_fixture_path(
        "MFRM_GMFRM_BROADER_EXPERIMENTAL_EXPOSURE_DECISION_REVIEW_FIXTURE",
        joinpath("test", "fixtures", "gmfrm_broader_experimental_exposure_decision_review.json"))
    if !isempty(gmfrm_broader_experimental_exposure_decision_review_fixture)
        check_gmfrm_broader_experimental_exposure_decision_review_fixture(
            gmfrm_broader_experimental_exposure_decision_review_fixture,
        )
    end
    gmfrm_guarded_exposure_review_fixture = optional_fixture_path("MFRM_GMFRM_GUARDED_EXPOSURE_REVIEW_FIXTURE", joinpath("test", "fixtures", "gmfrm_guarded_exposure_review.json"))
    if !isempty(gmfrm_guarded_exposure_review_fixture)
        check_gmfrm_guarded_exposure_review_fixture(
            gmfrm_guarded_exposure_review_fixture,
        )
    end
    gmfrm_bridge_fixture = optional_source_bridge_fixture_path(
        "MFRM_SOURCE_GMFRM_BRIDGESTAN_FIXTURE",
        joinpath("test", "fixtures", "source_gmfrm_bridge_logdensity.json"),
        joinpath("test", "stan", "source_gmfrm_fixture.stan"))
    if !isempty(gmfrm_bridge_fixture)
        check_source_bridge_fixture(
            gmfrm_bridge_fixture,
            gmfrm_target;
            expected_schema = "bayesianmgmfrm.source_gmfrm_bridge_logdensity.v1",
            expected_stan_model = "test/stan/source_gmfrm_fixture.stan",
        )
        check_gmfrm_bridge_direct_fixture(gmfrm_bridge_fixture, gmfrm_candidate)
    end
    @test_throws ArgumentError LogDensityProblems.logdensity(gmfrm_target, gmfrm_raw_params[1:end-1])
    @test_throws ArgumentError LogDensityProblems.logdensity(gmfrm_target, fill(Inf, gmfrm_raw_blueprint.n_parameters))
    @test_throws ArgumentError BayesianMGMFRM._gmfrm_promotion_candidate_diagnostics(
        gmfrm_candidate,
        gmfrm_raw_params;
        finite_difference_coords = [0],
    )
    @test_throws ArgumentError BayesianMGMFRM._gmfrm_promotion_candidate_transform_diagnostics(
        gmfrm_candidate,
        gmfrm_raw_params[1:end-1],
    )
    @test_throws ArgumentError BayesianMGMFRM._gmfrm_promotion_candidate_pointwise_fixture(
        gmfrm_preview,
        gmfrm_params[1:end-1],
    )
    @test_throws ArgumentError BayesianMGMFRM._gmfrm_promotion_candidate_pointwise_fixture(
        gmfrm_candidate,
        gmfrm_raw_params[1:end-1],
    )
    @test_throws ArgumentError BayesianMGMFRM._gmfrm_promotion_candidate_sampler_diagnostics(
        gmfrm_candidate,
        gmfrm_raw_params[1:end-1],
    )
    @test_throws ArgumentError BayesianMGMFRM._gmfrm_promotion_candidate_sampler_diagnostics(
        gmfrm_candidate,
        gmfrm_raw_params;
        rhat_threshold = 1.0,
    )
    @test_throws ArgumentError initial_params(gmfrm_target; value = Inf)
    @test_throws ArgumentError BayesianMGMFRM._SourceFixturePrior(; person_sd = 0.0)
    @test_throws ArgumentError BayesianMGMFRM._source_fixture_logdensity(identified_design)
    @test_throws ArgumentError BayesianMGMFRM._gmfrm_promotion_candidate_logdensity(identified_design)
    @test_throws ArgumentError BayesianMGMFRM._gmfrm_fit_ready_candidate_blueprint(identified_design)
    @test length(gmfrm_source_values) == length(gmfrm_predictors)
    @test all(row -> row.kernel === :gmfrm_source_aligned, gmfrm_source_values)
    @test all(row -> row.fixture_only && !row.fit_ready, gmfrm_source_values)
    gmfrm_row2_values = [0.0, 1.6 * (0.55 - (-0.1)), 1.6 * (0.55 - (-0.1)) + 1.6 * (0.55 - 0.1)]
    gmfrm_row2_value = only(filter(row -> row.row == 2 && row.category == 1, gmfrm_source_values))
    @test gmfrm_row2_value.observed
    @test gmfrm_row2_value.person_value ≈ 0.3
    @test gmfrm_row2_value.rater_value ≈ -0.05
    @test gmfrm_row2_value.item_value ≈ -0.2
    @test gmfrm_row2_value.location_value ≈ 0.55
    @test gmfrm_row2_value.item_discrimination_value ≈ 2.0
    @test gmfrm_row2_value.rater_consistency_value ≈ 0.8
    @test gmfrm_row2_value.scale_value ≈ 1.6
    @test gmfrm_row2_value.step_values ≈ [-0.1]
    @test gmfrm_row2_value.step_sum ≈ -0.1
    @test gmfrm_row2_value.scaled_step_sum ≈ -0.16
    @test gmfrm_row2_value.eta ≈ gmfrm_row2_values[2]
    @test gmfrm_row2_value.log_probability ≈ gmfrm_row2_values[2] - test_logsumexp(gmfrm_row2_values)
    gmfrm_row3_values = [0.0, 0.6 * (0.0 - 0.25), 0.6 * (0.0 - 0.25) + 0.6 * (0.0 - (-0.25))]
    gmfrm_row3_value = only(filter(row -> row.row == 3 && row.category == 2, gmfrm_source_values))
    @test gmfrm_row3_value.observed
    @test gmfrm_row3_value.scale_value ≈ 0.6
    @test gmfrm_row3_value.step_values ≈ [0.25, -0.25]
    @test gmfrm_row3_value.step_sum ≈ 0.0
    @test isapprox(gmfrm_row3_value.eta, gmfrm_row3_values[3]; atol = 1e-12)
    @test gmfrm_row3_value.log_probability ≈ gmfrm_row3_values[3] - test_logsumexp(gmfrm_row3_values)
    @test [row.log_probability for row in filter(row -> row.observed, gmfrm_source_values)] ≈
        gmfrm_source_pointwise
    bad_gmfrm_item_sum = copy(gmfrm_params)
    bad_gmfrm_item_sum[5] = -0.1
    @test_throws ArgumentError BayesianMGMFRM._gmfrm_source_fixture_values(gmfrm_preview, bad_gmfrm_item_sum)
    bad_gmfrm_product = copy(gmfrm_params)
    bad_gmfrm_product[7] = 1.8
    @test_throws ArgumentError BayesianMGMFRM._gmfrm_source_fixture_values(gmfrm_preview, bad_gmfrm_product)
    bad_gmfrm_consistency = copy(gmfrm_params)
    bad_gmfrm_consistency[9] = -0.1
    @test_throws ArgumentError BayesianMGMFRM._gmfrm_source_fixture_values(gmfrm_preview, bad_gmfrm_consistency)
    @test_throws ArgumentError BayesianMGMFRM._gmfrm_source_fixture_values(identified_design, gmfrm_params)
    @test_throws ArgumentError linear_predictor_values(gmfrm_spec, zeros(length(gmfrm_preview.parameter_names)); preview = true)
    @test_throws ArgumentError linear_predictor_values(gmfrm_preview, zeros(length(gmfrm_preview.parameter_names)))
    @test_throws ArgumentError predictive_probabilities(gmfrm_preview, zeros(1, length(gmfrm_preview.parameter_names)))
    @test_throws ArgumentError getdesign(gmfrm_spec)
    @test_throws ArgumentError fit(gmfrm_spec; ndraws = 1, warmup = 0)
    gmfrm_experimental_fit = fit(gmfrm_spec;
        experimental = true,
        ndraws = 4,
        warmup = 4,
        chains = 2,
        step_size = 0.03,
        seed = 20260627,
        max_depth = 3,
        metric = :unit)
    @test gmfrm_experimental_fit isa GMFRMFit
    @test isempty(RuntimePublicLanguagePolicy.runtime_language_violations([
        "actual GMFRMFit show" => sprint(show, gmfrm_experimental_fit),
        "actual GMFRMFit text/plain" =>
            sprint(show, MIME"text/plain"(), gmfrm_experimental_fit),
    ]))
    @test_throws ArgumentError facets_report(gmfrm_experimental_fit)
    @test_throws ArgumentError facets_compatibility_stats(gmfrm_experimental_fit)
    @test gmfrm_experimental_fit.design.spec.family === :gmfrm
    @test gmfrm_experimental_fit.design.spec.discrimination === :rater
    @test gmfrm_experimental_fit.backend === :advancedhmc
    @test gmfrm_experimental_fit.sampler === :nuts
    @test size(gmfrm_experimental_fit.draws, 1) == 8
    @test size(gmfrm_experimental_fit.draws, 2) ==
        length(gmfrm_experimental_fit.diagnostic_surface.raw_parameter_names)
    @test size(gmfrm_experimental_fit.direct_draws, 1) == 8
    @test size(gmfrm_experimental_fit.direct_pointwise_loglikelihood) ==
        (8, identified_data.n)
    @test all(isfinite, gmfrm_experimental_fit.log_posterior)
    gmfrm_standardized_residuals = predictive_standardized_residuals(
        gmfrm_experimental_fit;
        draw_indices = [2, 1],
    )
    @test gmfrm_standardized_residuals.family === :gmfrm
    @test gmfrm_standardized_residuals.draw_indices == (2, 1)
    @test size(gmfrm_standardized_residuals.values) == (2, identified_data.n)
    @test gmfrm_standardized_residuals.n_valid +
        gmfrm_standardized_residuals.n_excluded == 2 * identified_data.n
    @test pointwise_loglikelihood_matrix(gmfrm_experimental_fit) ==
        gmfrm_experimental_fit.direct_pointwise_loglikelihood
    gmfrm_direct_llmat = pointwise_loglikelihood_matrix(
        gmfrm_experimental_fit.design,
        gmfrm_experimental_fit.direct_draws)
    gmfrm_raw_llmat = pointwise_loglikelihood_matrix(
        gmfrm_experimental_fit.design,
        gmfrm_experimental_fit.draws;
        parameter_space = :raw)
    @test gmfrm_direct_llmat ≈
        gmfrm_experimental_fit.direct_pointwise_loglikelihood
    @test gmfrm_raw_llmat ≈
        gmfrm_experimental_fit.direct_pointwise_loglikelihood
    @test_throws ArgumentError pointwise_loglikelihood_matrix(
        gmfrm_experimental_fit.design,
        gmfrm_experimental_fit.draws)
    @test_throws ArgumentError pointwise_loglikelihood_matrix(
        gmfrm_experimental_fit.design,
        gmfrm_experimental_fit.direct_draws;
        parameter_space = :raw)
    @test loglikelihood(gmfrm_experimental_fit) ==
        gmfrm_experimental_fit.direct_loglikelihood
    @test logprior(gmfrm_experimental_fit) ≈
        gmfrm_experimental_fit.log_posterior .-
        gmfrm_experimental_fit.direct_loglikelihood
    @test logposterior(gmfrm_experimental_fit) ==
        gmfrm_experimental_fit.log_posterior
    @test loglikelihood(gmfrm_experimental_fit; draw_indices = [2, 1]) ==
        gmfrm_experimental_fit.direct_loglikelihood[[2, 1]]
    @test length(logprior(gmfrm_experimental_fit;
        ndraws = 2,
        rng = MersenneTwister(20260629))) == 2
    gmfrm_experimental_metadata = fit_metadata(gmfrm_experimental_fit)
    @test gmfrm_experimental_metadata.public_fit
    @test gmfrm_experimental_metadata.experimental_public
    @test gmfrm_experimental_metadata.status_policy.status_label ===
        :experimental_public
    @test :broad_generalized_fit in
        gmfrm_experimental_metadata.status_policy.blocked_claims
    @test gmfrm_experimental_metadata.scope === :scalar_gmfrm_fit_ready_candidate
    @test gmfrm_experimental_metadata.density_space === :raw_unconstrained
    @test gmfrm_experimental_metadata.n_direct_parameters ==
        size(gmfrm_experimental_fit.direct_draws, 2)
    @test isequal(
        gmfrm_experimental_metadata,
        fit_metadata(gmfrm_experimental_fit; view = :full),
    )
    gmfrm_public_metadata = fit_metadata(
        gmfrm_experimental_fit;
        view = :public,
    )
    @test gmfrm_public_metadata.schema ==
        "bayesianmgmfrm.fit_metadata_public.v1"
    @test gmfrm_public_metadata.family === :gmfrm
    @test gmfrm_public_metadata.stability === :experimental
    @test gmfrm_public_metadata.estimation_status === :experimental
    @test gmfrm_public_metadata.raw_parameter_names ==
        gmfrm_experimental_metadata.raw_parameter_names
    @test isempty(intersect(
        Set(structured_field_names(gmfrm_public_metadata)),
        PRIVATE_READER_FIT_FIELDS,
    ))
    @test reader_payload_is_identity_free(gmfrm_public_metadata)
    @test_throws ArgumentError fit_metadata(
        gmfrm_experimental_fit;
        view = :unknown,
    )
    gmfrm_fit_audit = model_surface_audit(gmfrm_experimental_fit)
    @test all(row -> row.current_status === :experimental_public,
        gmfrm_fit_audit)
    @test all(row -> row.public_fit && row.experimental_public && row.fit_ready,
        gmfrm_fit_audit)
    @test any(row -> row.block === :rater_consistency &&
        row.raw_coordinate === :log_rater_consistency &&
        row.prior_scale === :log_consistency_sd &&
        :broad_generalized_fit in row.blocked_claims,
        gmfrm_fit_audit)
    gmfrm_experimental_diagnostics = diagnostics(gmfrm_experimental_fit)
    @test gmfrm_experimental_diagnostics.schema ==
        "bayesianmgmfrm.gmfrm_experimental_fit_diagnostics.v1"
    @test gmfrm_experimental_diagnostics.public_fit
    @test gmfrm_experimental_diagnostics.experimental_public
    @test gmfrm_experimental_diagnostics.parameter_layout.schema ==
        "bayesianmgmfrm.fit_ready_parameter_layout.v1"
    @test gmfrm_experimental_diagnostics.parameter_layout.raw_parameter_names ==
        gmfrm_experimental_fit.diagnostic_surface.raw_parameter_names
    @test gmfrm_experimental_diagnostics.parameter_layout.constrained_parameter_names ==
        gmfrm_experimental_fit.diagnostic_surface.direct_parameter_names
    @test gmfrm_experimental_diagnostics.diagnostic_row_policy.family === :gmfrm
    @test gmfrm_experimental_diagnostics.diagnostic_row_policy.parameter_spaces ==
        (:raw_unconstrained, :direct_constrained)
    @test gmfrm_experimental_diagnostics.diagnostic_row_policy.rhat_ess_status ===
        :rank_normalized_available
    @test gmfrm_experimental_diagnostics.summary.total_draws == 8
    @test isequal(
        gmfrm_experimental_diagnostics,
        diagnostics(gmfrm_experimental_fit; view = :full),
    )
    gmfrm_public_diagnostics = diagnostics(
        gmfrm_experimental_fit;
        view = :public,
    )
    @test gmfrm_public_diagnostics.schema ==
        "bayesianmgmfrm.diagnostics_public.v1"
    @test gmfrm_public_diagnostics.family === :gmfrm
    @test gmfrm_public_diagnostics.stability === :experimental
    @test public_portable_numeric_summary_matches(
        gmfrm_public_diagnostics.summary.raw_diagnostic_metrics,
        gmfrm_experimental_diagnostics.summary.raw_diagnostic_metrics,
    )
    @test gmfrm_public_diagnostics.parameter_layout.raw_parameter_names ==
        gmfrm_experimental_diagnostics.parameter_layout.raw_parameter_names
    @test isempty(intersect(
        Set(structured_field_names(gmfrm_public_diagnostics)),
        PRIVATE_READER_FIT_FIELDS,
    ))
    @test reader_payload_is_identity_free(gmfrm_public_diagnostics)
    @test_throws ArgumentError diagnostics(
        gmfrm_experimental_fit;
        view = :unknown,
    )
    @test length(sampler_diagnostics(gmfrm_experimental_fit)) == 2
    @test all(row -> row.diagnostic_row === :sampler_chain &&
        row.parameter_space === :raw_unconstrained &&
        row.diagnostic_method === :sampler_chain_summary,
        sampler_diagnostics(gmfrm_experimental_fit))
    @test length(mcmc_diagnostics(gmfrm_experimental_fit)) ==
        size(gmfrm_experimental_fit.draws, 2)
    @test all(row -> row.diagnostic_row === :parameter &&
        row.parameter_space === :raw_unconstrained &&
        row.diagnostic_method === :rank_normalized_split_rhat_bulk_tail_ess &&
        row.diagnostic_status === :rank_normalized_available &&
        row.flag === row.rank_normalized_flag,
        mcmc_diagnostics(gmfrm_experimental_fit))
    @test length(parameter_block_diagnostics(gmfrm_experimental_fit)) >= 1
    @test all(row -> row.diagnostic_row === :parameter_block &&
        row.parameter_space === :raw_unconstrained &&
        row.diagnostic_method === :rank_normalized_split_rhat_bulk_tail_ess &&
        row.diagnostic_status === :rank_normalized_available,
        parameter_block_diagnostics(gmfrm_experimental_fit))
    @test all(row -> row.parameter_space === :direct_constrained &&
        row.diagnostic_method === :rank_normalized_split_rhat_bulk_tail_ess &&
        ((row.quality_gate_applicable &&
                row.diagnostic_status === :rank_normalized_available &&
                row.flag === row.rank_normalized_flag) ||
            (!row.quality_gate_applicable &&
                row.diagnostic_status === :structurally_fixed &&
                row.flag === :structurally_fixed &&
                row.classical_compatibility_flag === :structurally_fixed)),
        gmfrm_experimental_diagnostics.direct_parameter_rows)
    @test all(row -> row.diagnostic_row === :parameter_block &&
        row.parameter_space === :direct_constrained &&
        row.diagnostic_method === :rank_normalized_split_rhat_bulk_tail_ess &&
        row.diagnostic_status in
            (:rank_normalized_available, :structurally_fixed),
        gmfrm_experimental_diagnostics.direct_block_rows)
    gmfrm_experimental_artifact =
        fit_artifact(gmfrm_experimental_fit; include_environment = false)
    @test gmfrm_experimental_artifact.schema ==
        "bayesianmgmfrm.gmfrm_experimental_fit_artifact.v1"
    @test gmfrm_experimental_artifact.public_fit
    @test gmfrm_experimental_artifact.experimental_public
    @test gmfrm_experimental_artifact.entrypoint ==
        "BayesianMGMFRM.Experimental.fit(spec)"
    @test gmfrm_experimental_artifact.legacy_entrypoint ==
        "BayesianMGMFRM.fit(spec; experimental = true)"
    @test gmfrm_experimental_artifact.reproducibility.diagnostic_policy.diagnostic_contract ===
        :rank_normalized_rhat_bulk_tail_ess_v1
    @test gmfrm_experimental_artifact.reproducibility.diagnostic_policy.diagnostic_contract_details.id ===
        :rank_normalized_rhat_bulk_tail_ess_v1
    @test gmfrm_experimental_artifact.public_target_label ===
        :guarded_scalar_gmfrm_logdensity
    @test gmfrm_experimental_artifact.public_target_description ==
        "guarded scalar GMFRM log density"
    @test gmfrm_experimental_artifact.internal_target_constructor ===
        :_gmfrm_promotion_candidate_logdensity
    @test gmfrm_experimental_artifact.internal_sampler_diagnostic_constructor ===
        :_gmfrm_promotion_candidate_sampler_diagnostics
    gmfrm_public_artifact = fit_artifact(
        gmfrm_experimental_fit;
        view = :public,
        include_environment = false,
    )
    @test gmfrm_public_artifact.schema ==
        "bayesianmgmfrm.fit_artifact_public.v1"
    @test gmfrm_public_artifact.stability === :experimental
    @test gmfrm_public_artifact.content_hash.value ==
        artifact_content_hash(gmfrm_public_artifact)
    @test :internal_target_constructor ∉ keys(gmfrm_public_artifact)
    @test :internal_sampler_diagnostic_constructor ∉
        keys(gmfrm_public_artifact)
    @test :fixture_provenance ∉ keys(gmfrm_public_artifact)
    gmfrm_public_surface = model_surface_audit(
        gmfrm_experimental_fit;
        view = :public,
    )
    @test all(row -> row.execution_status === :experimental &&
        row.fit_available &&
        row.fit_entrypoint == "BayesianMGMFRM.Experimental.fit(spec)" &&
        row.claim_scope === :scalar_rater_consistency_only &&
        :block_status ∉ keys(row),
        gmfrm_public_surface)
    @test any(row -> row.declaration_status === :specified_only,
        gmfrm_public_surface)
    @test gmfrm_experimental_artifact.evidence_artifact_schema_policy.artifact_kind ===
        :gmfrm_experimental_fit_artifact
    @test :broad_generalized_fit in
        gmfrm_experimental_artifact.evidence_artifact_schema_policy.claim_policy.unsupported_claims
    @test gmfrm_experimental_artifact.evidence_artifact_schema_policy.environment_policy.include_environment ===
        false
    @test gmfrm_experimental_artifact.density_space === :raw_unconstrained
    @test gmfrm_experimental_artifact.raw_prior_control_manifest.schema ==
        "bayesianmgmfrm.generalized_raw_prior_control_manifest.v1"
    @test gmfrm_experimental_artifact.raw_prior_control_manifest.resolved
    @test gmfrm_experimental_artifact.raw_prior_control_manifest.summary.all_active_scales_resolved
    @test any(row -> row.raw_block === :log_rater_consistency &&
        row.scale_parameter === :log_consistency_sd &&
        row.scale == gmfrm_experimental_fit.prior.log_consistency_sd &&
        row.scale_status === :resolved_from_source_fixture_prior,
        gmfrm_experimental_artifact.raw_prior_control_manifest.rows)
    @test any(row -> row.raw_block === :log_item_discrimination_free &&
        row.scale_parameter === :log_discrimination_sd &&
        row.scale == gmfrm_experimental_fit.prior.log_discrimination_sd,
        gmfrm_experimental_artifact.raw_prior_control_manifest.rows)
    @test isequal(gmfrm_experimental_artifact.parameter_layout,
        gmfrm_experimental_diagnostics.parameter_layout)
    @test gmfrm_experimental_artifact.raw_parameter_names ==
        gmfrm_experimental_fit.diagnostic_surface.raw_parameter_names
    @test gmfrm_experimental_artifact.direct_parameter_names ==
        gmfrm_experimental_fit.diagnostic_surface.direct_parameter_names
    @test size(gmfrm_experimental_artifact.pointwise_loglikelihood) ==
        (8, identified_data.n)
    @test gmfrm_experimental_artifact.raw_to_direct_transform ==
        gmfrm_experimental_artifact.parameter_layout.transforms
    @test !isempty(gmfrm_experimental_artifact.raw_to_direct_transform)
    @test gmfrm_experimental_artifact.raw_posterior_row_schema.schema ==
        "bayesianmgmfrm.posterior_summary_row_schema.v1"
    @test gmfrm_experimental_artifact.raw_posterior_row_schema.parameter_space ===
        :raw_unconstrained
    @test gmfrm_experimental_artifact.raw_posterior_row_schema.parameter_names ==
        gmfrm_experimental_artifact.raw_parameter_names
    @test gmfrm_experimental_artifact.raw_posterior_row_schema.row_fields ==
        propertynames(first(gmfrm_experimental_artifact.posterior_summary))
    @test gmfrm_experimental_artifact.direct_posterior_row_schema.schema ==
        "bayesianmgmfrm.posterior_summary_row_schema.v1"
    @test gmfrm_experimental_artifact.direct_posterior_row_schema.parameter_space ===
        :constrained_direct
    @test gmfrm_experimental_artifact.direct_posterior_row_schema.parameter_names ==
        gmfrm_experimental_artifact.direct_parameter_names
    @test gmfrm_experimental_artifact.direct_posterior_row_schema.row_fields ==
        propertynames(first(gmfrm_experimental_artifact.direct_posterior_summary))
    @test !isempty(gmfrm_experimental_artifact.fixture_provenance)
    @test isnothing(gmfrm_experimental_artifact.raw_draws)
    @test isnothing(gmfrm_experimental_artifact.direct_draws)
    @test gmfrm_experimental_artifact.content_hash.value ==
        artifact_content_hash(gmfrm_experimental_artifact)
    @test gmfrm_experimental_artifact.archive_manifest.content_hash ==
        gmfrm_experimental_artifact.content_hash
    gmfrm_report = fit_report(gmfrm_experimental_fit;
        draw_indices = [1, 2],
        include_loo = false,
        artifact_include_environment = false)
    gmfrm_report_hash = artifact_content_hash(gmfrm_report)
    gmfrm_public_report = fit_report_public(gmfrm_report)
    @test gmfrm_public_report.schema ==
        "bayesianmgmfrm.fit_report_public.v1"
    @test gmfrm_public_report.status === :experimental
    @test gmfrm_public_report.source_report.content_hash ==
        BayesianMGMFRM._public_fit_report_content_hash_record(gmfrm_report).value
    @test gmfrm_report.category_functioning.status === :not_requested
    @test gmfrm_report.rater_homogeneity.status === :not_requested
    gmfrm_practitioner_report = fit_report(gmfrm_experimental_fit;
        include_category_functioning = true,
        include_rater_homogeneity = true,
        include_posterior_predictive = false,
        include_calibration = false,
        include_waic = false,
        include_loo = false,
        include_artifact = false)
    @test gmfrm_practitioner_report.report_status === :complete
    @test gmfrm_practitioner_report.category_functioning.status === :unsupported
    @test gmfrm_practitioner_report.rater_homogeneity.status === :unsupported
    @test artifact_content_hash(gmfrm_report) == gmfrm_report_hash
    @test !hasproperty(gmfrm_public_report, :status_policy)
    @test !hasproperty(gmfrm_public_report, :manifest)
    @test !occursin(r"experimental_public|guarded_local_fit|next_gate|test/fixtures/|scripts/generate_",
        JSON3.write(gmfrm_public_report))
    @test isempty(RuntimePublicLanguagePolicy.runtime_language_violations([
        "actual GMFRM public report" => JSON3.write(gmfrm_public_report),
        "actual GMFRM public Markdown" =>
            fit_report_markdown(gmfrm_public_report; max_rows = 2),
    ]))
    @test gmfrm_report.prior_policy.status === :computed
    @test gmfrm_report.prior_policy.summary.raw_coordinate_generalized_priors
    @test !gmfrm_report.prior_policy.summary.direct_scale_generalized_priors_enabled
    @test gmfrm_report.prior_policy.summary.jacobian_policy ===
        :none_raw_coordinate_density
    @test gmfrm_report.prior_policy.summary.raw_prior_control_manifest_recorded
    @test gmfrm_report.prior_policy.summary.raw_prior_control_all_active_scales_resolved
    @test gmfrm_report.prior_policy.raw_prior_control_manifest.schema ==
        "bayesianmgmfrm.generalized_raw_prior_control_manifest.v1"
    @test any(row -> row.raw_block === :log_rater_consistency &&
        row.scale == gmfrm_experimental_fit.prior.log_consistency_sd,
        gmfrm_report.prior_policy.raw_prior_control_manifest.rows)
    @test any(row -> row.block === :log_rater_consistency &&
        row.parameter_space === :raw_log_positive_coordinate &&
        row.scale_parameter === :log_consistency_sd &&
        row.status === :active,
        gmfrm_report.prior_policy.rows)
    @test any(row -> row.block === :direct_scale_generalized_priors &&
        row.status === :blocked &&
        row.jacobian_policy === :requires_future_log_jacobian_policy,
        gmfrm_report.prior_policy.rows)
    @test gmfrm_report.pooling_policy.status === :computed
    @test gmfrm_report.pooling_policy.summary.independent_priors_default
    @test !gmfrm_report.pooling_policy.summary.hierarchical_pooling_active
    @test !gmfrm_report.pooling_policy.summary.partial_pooling_claims_allowed
    @test any(row -> row.pooling === :hierarchical_rater_consistency_pooling &&
        row.status === :blocked,
        gmfrm_report.pooling_policy.rows)
    gmfrm_cache_key = fit_cache_key(gmfrm_spec;
        experimental = true,
        backend = :advancedhmc,
        ndraws = 4,
        warmup = 4,
        chains = 2,
        step_size = 0.03,
        seed = 20260627,
        max_depth = 3,
        metric = :unit)
    @test length(gmfrm_cache_key) == 64
    @test gmfrm_cache_key == fit_cache_key(gmfrm_experimental_fit.design;
        experimental = true,
        backend = :advancedhmc,
        ndraws = 4,
        warmup = 4,
        chains = 2,
        step_size = 0.03,
        seed = 20260627,
        max_depth = 3,
        metric = :unit)
    @test gmfrm_cache_key != fit_cache_key(gmfrm_spec;
        experimental = true,
        backend = :advancedhmc,
        ndraws = 4,
        warmup = 4,
        chains = 2,
        step_size = 0.03,
        seed = 20260628,
        max_depth = 3,
        metric = :unit)
    @test_throws ArgumentError fit_cache_key(gmfrm_spec;
        experimental = true,
        backend = :julia,
        ndraws = 2,
        warmup = 0,
        chains = 1,
        step_size = 0.03,
        seed = 20260628)
    gmfrm_cache_dir = mktempdir()
    gmfrm_cache_path = joinpath(gmfrm_cache_dir, "gmfrm_experimental_fit.jls")
    gmfrm_cache_record = save_fit_cache(gmfrm_cache_path, gmfrm_experimental_fit;
        cache_key = gmfrm_cache_key)
    @test gmfrm_cache_record.object === :fit_cache
    @test gmfrm_cache_record.fit isa GMFRMFit
    @test gmfrm_cache_record.cache_key == gmfrm_cache_key
    @test gmfrm_cache_record.artifact.schema ==
        "bayesianmgmfrm.gmfrm_experimental_fit_artifact.v1"
    @test load_fit_cache(gmfrm_cache_path;
        expected_cache_key = gmfrm_cache_key) isa GMFRMFit
    @test load_fit_cache(gmfrm_cache_path;
        expected_cache_key = gmfrm_cache_key).draws == gmfrm_experimental_fit.draws
    gmfrm_reproduction_manifest = fit_reproduction_manifest(gmfrm_experimental_fit;
        artifact = gmfrm_experimental_artifact,
        source_path = "memory://gmfrm_experimental_artifact",
        cache_record = gmfrm_cache_record,
        cache_path = gmfrm_cache_path)
    @test gmfrm_reproduction_manifest.status === :ready
    @test gmfrm_reproduction_manifest.family === :gmfrm
    @test gmfrm_reproduction_manifest.fast_cached_draws.status === :ready
    @test gmfrm_reproduction_manifest.fast_cached_draws.n_draws == 8
    @test gmfrm_reproduction_manifest.fast_cached_draws.backend === :advancedhmc
    @test gmfrm_reproduction_manifest.fast_cached_draws.content_hash ==
        gmfrm_cache_record.artifact_content_hash
    gmfrm_cached_path = joinpath(gmfrm_cache_dir, "gmfrm_cached_fit.jls")
    gmfrm_cached_record = cached_fit(gmfrm_spec;
        cache_path = gmfrm_cached_path,
        experimental = true,
        return_record = true,
        backend = :advancedhmc,
        ndraws = 2,
        warmup = 0,
        chains = 1,
        step_size = 0.03,
        seed = 20260635,
        max_depth = 1,
        metric = :unit)
    @test gmfrm_cached_record.object === :fit_cache
    @test gmfrm_cached_record.fit isa GMFRMFit
    gmfrm_cached_hit = cached_fit(gmfrm_spec;
        cache_path = gmfrm_cached_path,
        experimental = true,
        backend = :advancedhmc,
        ndraws = 2,
        warmup = 0,
        chains = 1,
        step_size = 0.03,
        seed = 20260635,
        max_depth = 1,
        metric = :unit)
    @test gmfrm_cached_hit.draws == gmfrm_cached_record.fit.draws
    @test_throws ArgumentError cached_fit(gmfrm_spec;
        cache_path = gmfrm_cached_path,
        experimental = true,
        backend = :advancedhmc,
        ndraws = 2,
        warmup = 0,
        chains = 1,
        step_size = 0.03,
        seed = 20260636,
        max_depth = 1,
        metric = :unit)
    @test waic(gmfrm_experimental_fit).n_draws == 8
    @test waic(gmfrm_experimental_fit.design,
        gmfrm_experimental_fit.direct_draws).waic ≈
        waic(gmfrm_experimental_fit).waic
    @test waic(gmfrm_experimental_fit.design,
        gmfrm_experimental_fit.draws;
        parameter_space = :raw).waic ≈
        waic(gmfrm_experimental_fit).waic
    @test loo(gmfrm_experimental_fit).n_draws == 8
    @test loo(gmfrm_experimental_fit.design,
        gmfrm_experimental_fit.draws;
        parameter_space = :raw).looic ≈
        loo(gmfrm_experimental_fit).looic
    @test psis_loo(gmfrm_experimental_fit.design,
        gmfrm_experimental_fit.draws;
        parameter_space = :raw, chain_ids=gmfrm_experimental_fit.chain_ids).looic ≈
        psis_loo(gmfrm_experimental_fit).looic
    gmfrm_comparison = compare_models(
        :gmfrm_a => gmfrm_experimental_fit,
        :gmfrm_b => gmfrm_experimental_fit;
        draw_indices = [1, 2])
    @test length(gmfrm_comparison) == 2
    @test all(row -> row.comparison_contract ===
        :same_observation_data_same_latent_dimensions, gmfrm_comparison)
    @test all(row -> row.model_family === :gmfrm, gmfrm_comparison)
    @test all(row -> row.thresholds === gmfrm_spec.thresholds, gmfrm_comparison)
    @test all(row -> row.dimensions == 1, gmfrm_comparison)
    @test all(row -> row.discrimination === :rater, gmfrm_comparison)
    @test all(row -> row.q_matrix === nothing, gmfrm_comparison)
    @test all(row -> row.data_signature ==
        gmfrm_spec.validation.data_signature, gmfrm_comparison)
    @test all(row -> row.category_levels ==
        identified_data.category_levels, gmfrm_comparison)
    @test length(waic_diagnostics(gmfrm_experimental_fit)) == identified_data.n
    @test length(waic_diagnostics(gmfrm_experimental_fit.design,
        gmfrm_experimental_fit.draws;
        parameter_space = :raw)) == identified_data.n
    @test length(loo_diagnostics(gmfrm_experimental_fit)) == identified_data.n
    @test length(loo_diagnostics(gmfrm_experimental_fit.design,
        gmfrm_experimental_fit.draws;
        parameter_space = :raw)) == identified_data.n
    gmfrm_probabilities =
        predictive_probabilities(gmfrm_experimental_fit; draw_indices = [1, 2])
    @test size(gmfrm_probabilities) ==
        (2, identified_data.n, length(identified_data.category_levels))
    @test all(draw -> all(row -> sum(gmfrm_probabilities[draw, row, :]) ≈ 1.0,
        1:identified_data.n), 1:2)
    @test all(row -> log(gmfrm_probabilities[1, row, identified_data.category[row]]) ≈
        gmfrm_experimental_fit.direct_pointwise_loglikelihood[1, row],
        1:identified_data.n)
    gmfrm_expected = expected_scores(gmfrm_experimental_fit; draw_indices = [1, 2])
    gmfrm_variances = predictive_variances(gmfrm_experimental_fit; draw_indices = [1, 2])
    gmfrm_residuals = predictive_residuals(gmfrm_experimental_fit; draw_indices = [1, 2])
    @test size(gmfrm_expected) == (2, identified_data.n)
    @test size(gmfrm_variances) == (2, identified_data.n)
    @test size(gmfrm_residuals) == (2, identified_data.n)
    @test all(>=(0.0), gmfrm_variances)
    for draw in 1:2, row in 1:identified_data.n
        manual_mean = sum(identified_data.category_levels[k] *
            gmfrm_probabilities[draw, row, k]
            for k in eachindex(identified_data.category_levels))
        manual_second = sum(identified_data.category_levels[k]^2 *
            gmfrm_probabilities[draw, row, k]
            for k in eachindex(identified_data.category_levels))
        @test gmfrm_expected[draw, row] ≈ manual_mean
        @test gmfrm_variances[draw, row] ≈ manual_second - manual_mean^2 atol = 1e-12
        @test gmfrm_residuals[draw, row] ≈ identified_data.score[row] - gmfrm_expected[draw, row]
    end
    gmfrm_residual_rows = residual_summary(gmfrm_experimental_fit;
        by = :rater,
        draw_indices = [1, 2])
    @test length(gmfrm_residual_rows) == length(identified_data.rater_levels)
    @test all(row -> row.facet === :rater, gmfrm_residual_rows)
    @test all(row -> row.n_draws == 2, gmfrm_residual_rows)
    @test all(row -> row.caveat ===
        :posterior_predictive_residual_screening_not_confirmatory,
        gmfrm_residual_rows)
    gmfrm_rater_diag = rater_diagnostics(gmfrm_experimental_fit;
        draw_indices = [1, 2])
    @test length(gmfrm_rater_diag) == length(identified_data.rater_levels)
    @test [row.level for row in gmfrm_rater_diag] == identified_data.rater_levels
    @test all(row -> row.facet === :rater, gmfrm_rater_diag)
    @test all(row -> row.model_family === :gmfrm, gmfrm_rater_diag)
    @test all(row -> row.method === :posterior_rater_diagnostics, gmfrm_rater_diag)
    @test all(row -> row.n_draws == 2, gmfrm_rater_diag)
    @test all(row -> row.discrimination_modeled == true, gmfrm_rater_diag)
    @test all(row -> row.discrimination_parameter === :rater_consistency,
        gmfrm_rater_diag)
    @test all(row -> row.discrimination_scale === :positive_consistency_multiplier,
        gmfrm_rater_diag)
    @test all(row -> row.fit_statistics_available == false, gmfrm_rater_diag)
    @test all(row -> row.infit_mean === missing && row.outfit_mean === missing,
        gmfrm_rater_diag)
    @test all(row -> row.fit_flag === missing, gmfrm_rater_diag)
    @test all(row -> row.caveat ===
        :rater_diagnostics_screening_not_confirmatory,
        gmfrm_rater_diag)
    for row in gmfrm_rater_diag
        level_index = findfirst(==(row.level), identified_data.rater_levels)
        obs = findall(==(level_index), identified_data.rater)
        severity_index = gmfrm_experimental_fit.design.blocks[:rater][level_index]
        consistency_index =
            gmfrm_experimental_fit.design.blocks[:rater_consistency][level_index]
        severity_by_draw = [
            Float64(gmfrm_experimental_fit.direct_draws[draw, severity_index])
            for draw in 1:2
        ]
        consistency_by_draw = [
            Float64(gmfrm_experimental_fit.direct_draws[draw, consistency_index])
            for draw in 1:2
        ]
        residual_row = only(filter(candidate -> candidate.level == row.level,
            gmfrm_residual_rows))
        @test row.rater == row.level
        @test row.rater_index == level_index
        @test row.n_observations == length(obs)
        @test row.severity_parameter_name ==
            gmfrm_experimental_fit.design.parameter_names[severity_index]
        @test row.discrimination_parameter_name ==
            gmfrm_experimental_fit.design.parameter_names[consistency_index]
        @test row.severity_mean ≈ sum(severity_by_draw) / length(severity_by_draw)
        @test row.discrimination_mean ≈
            sum(consistency_by_draw) / length(consistency_by_draw)
        @test row.discrimination_lower <=
            row.discrimination_median <= row.discrimination_upper
        @test row.residual_mean ≈ residual_row.residual_mean
        @test row.absolute_residual_mean ≈ residual_row.absolute_residual_mean
        @test row.rmse_mean ≈ residual_row.rmse_mean
        @test row.residual_flag === residual_row.flag
    end
    gmfrm_replicated = posterior_predict(gmfrm_experimental_fit;
        draw_indices = [1, 2],
        rng = MersenneTwister(20260628))
    @test size(gmfrm_replicated) == (2, identified_data.n)
    @test all(score -> score in identified_data.category_levels, gmfrm_replicated)
    gmfrm_ppc = posterior_predictive_check(gmfrm_experimental_fit;
        ndraws = 3,
        rng = MersenneTwister(20260629))
    @test size(gmfrm_ppc.replicated_scores) == (3, identified_data.n)
    @test gmfrm_ppc.category_levels == identified_data.category_levels
    @test gmfrm_ppc.person_levels == identified_data.person_levels
    @test gmfrm_ppc.rater_levels == identified_data.rater_levels
    @test gmfrm_ppc.item_levels == identified_data.item_levels
    gmfrm_ppc_summary = predictive_check_summary(gmfrm_ppc; interval = 0.8)
    expected_gmfrm_ppc_rows = 1 + length(identified_data.category_levels) +
        length(identified_data.person_levels) + length(identified_data.rater_levels) +
        length(identified_data.item_levels) +
        sum(length(levels) for levels in values(identified_data.optional_levels))
    @test length(gmfrm_ppc_summary) == expected_gmfrm_ppc_rows
    @test all(row -> row.n_replicates == 3, gmfrm_ppc_summary)
    @test all(row -> row.flag in (:ok, :outside_interval), gmfrm_ppc_summary)
    gmfrm_simulated_direct = simulate_responses(gmfrm_spec, gmfrm_params;
        preview = true,
        rng = MersenneTwister(20260631),
        output = :scores)
    gmfrm_simulated_raw = simulate_responses(gmfrm_spec, gmfrm_raw_params;
        preview = true,
        parameter_space = :raw,
        rng = MersenneTwister(20260631),
        output = :scores)
    @test gmfrm_simulated_direct == gmfrm_simulated_raw
    @test length(gmfrm_simulated_direct) == identified_data.n
    @test all(score -> score in identified_data.category_levels, gmfrm_simulated_direct)
    @test_throws ArgumentError simulate_responses(gmfrm_spec, gmfrm_params;
        output = :scores)
    gmfrm_design_recovery_direct = parameter_recovery(
        gmfrm_preview,
        reshape(gmfrm_params, 1, :),
        gmfrm_params)
    @test length(gmfrm_design_recovery_direct) == length(gmfrm_params)
    @test all(row -> row.model_family === :gmfrm, gmfrm_design_recovery_direct)
    @test all(row -> row.parameter_space === :direct, gmfrm_design_recovery_direct)
    @test all(row -> row.density_space === :constrained_direct,
        gmfrm_design_recovery_direct)
    @test [row.parameter for row in gmfrm_design_recovery_direct] ==
        gmfrm_preview.parameter_names
    gmfrm_design_recovery_raw = parameter_recovery(
        gmfrm_preview,
        reshape(gmfrm_raw_params, 1, :),
        gmfrm_raw_params;
        parameter_space = :raw)
    @test [row.parameter for row in gmfrm_design_recovery_raw] ==
        gmfrm_fit_ready_blueprint.parameter_names
    @test all(row -> row.parameter_space === :raw, gmfrm_design_recovery_raw)
    @test all(row -> row.density_space === :raw_unconstrained,
        gmfrm_design_recovery_raw)
    gmfrm_direct_truth = [
        sum(gmfrm_experimental_fit.direct_draws[:, col]) /
            size(gmfrm_experimental_fit.direct_draws, 1)
        for col in axes(gmfrm_experimental_fit.direct_draws, 2)
    ]
    gmfrm_fit_recovery_direct =
        parameter_recovery(gmfrm_experimental_fit, gmfrm_direct_truth)
    @test length(gmfrm_fit_recovery_direct) == length(gmfrm_params)
    @test all(row -> row.model_family === :gmfrm, gmfrm_fit_recovery_direct)
    @test all(row -> row.parameter_space === :direct, gmfrm_fit_recovery_direct)
    @test all(row -> row.fit_ready && row.public_fit && row.experimental_public,
        gmfrm_fit_recovery_direct)
    @test maximum(abs(row.bias) for row in gmfrm_fit_recovery_direct) < 1e-12
    gmfrm_raw_truth = [
        sum(gmfrm_experimental_fit.draws[:, col]) /
            size(gmfrm_experimental_fit.draws, 1)
        for col in axes(gmfrm_experimental_fit.draws, 2)
    ]
    gmfrm_fit_recovery_raw = parameter_recovery(gmfrm_experimental_fit,
        gmfrm_raw_truth;
        parameter_space = :raw)
    @test length(gmfrm_fit_recovery_raw) == gmfrm_raw_blueprint.n_parameters
    @test [row.parameter for row in gmfrm_fit_recovery_raw] ==
        gmfrm_fit_ready_blueprint.parameter_names
    @test all(row -> row.parameter_space === :raw, gmfrm_fit_recovery_raw)
    @test parameter_recovery_summary(gmfrm_experimental_fit, gmfrm_direct_truth;
        by = :all)[1].n_parameters == length(gmfrm_params)
    @test length(parameter_recovery_plot_data(gmfrm_experimental_fit,
        gmfrm_direct_truth)) == length(gmfrm_params)
    gmfrm_calibration = calibration_table(gmfrm_experimental_fit;
        draw_indices = [1, 2],
        bins = 3,
        interval = 0.8)
    @test length(gmfrm_calibration) == 3
    @test sum(row.n_observations for row in gmfrm_calibration) == identified_data.n
    @test all(row -> row.target === :expected_score, gmfrm_calibration)
    @test all(row -> row.flag in (:ok, :outside_interval), gmfrm_calibration)
    gmfrm_category_calibration = calibration_table(gmfrm_experimental_fit;
        target = :category_probability,
        category = last(identified_data.category_levels),
        draw_indices = [1, 2],
        bins = 2)
    @test length(gmfrm_category_calibration) == 2
    @test all(row -> row.target === :category_probability, gmfrm_category_calibration)
    @test all(row -> row.category == last(identified_data.category_levels),
        gmfrm_category_calibration)
    gmfrm_all_category_calibration = calibration_table(gmfrm_experimental_fit;
        target = :category_probability,
        category = :all,
        draw_indices = [1, 2],
        bins = 2)
    @test length(gmfrm_all_category_calibration) ==
        2 * length(identified_data.category_levels)
    @test Set(row.category for row in gmfrm_all_category_calibration) ==
        Set(identified_data.category_levels)
    @test all(row -> row.target === :category_probability,
        gmfrm_all_category_calibration)
    gmfrm_all_calibration = calibration_table(gmfrm_experimental_fit;
        target = :all,
        draw_indices = [1, 2],
        bins = 2)
    @test length(gmfrm_all_calibration) ==
        2 * (1 + length(identified_data.category_levels))
    @test all(row -> row.target === :expected_score,
        gmfrm_all_calibration[1:2])
    @test Set(row.category for row in gmfrm_all_calibration[3:end]) ==
        Set(identified_data.category_levels)
    @test_throws ArgumentError posterior_predict(gmfrm_experimental_fit; ndraws = 0)
    @test_throws ArgumentError posterior_predictive_check(gmfrm_experimental_fit;
        ndraws = 2,
        draw_indices = [1])
    @test_throws ArgumentError calibration_table(gmfrm_experimental_fit; bins = 0)
    @test_throws ArgumentError fit(gmfrm_spec;
        experimental = true,
        backend = :julia,
        ndraws = 1,
        warmup = 0)
    @test_throws ArgumentError fit(gmfrm_spec;
        experimental = true,
        prior = MFRMPrior(),
        ndraws = 1,
        warmup = 0)

    q_matrix = Bool[1 0; 0 1]
    mgmfrm_spec = mfrm_spec(identified_data;
        family = :mgmfrm,
        dimensions = 2,
        q_matrix)
    @test mgmfrm_spec.family === :mgmfrm
    @test mgmfrm_spec.dimensions == 2
    @test mgmfrm_spec.dimension_labels == ["dim=1", "dim=2"]
    @test mgmfrm_spec.estimation_status === :specified_only
    @test mgmfrm_spec.q_matrix == q_matrix
    mgmfrm_q_validation = q_matrix_validation(mgmfrm_spec)
    @test mgmfrm_q_validation.schema ==
        "bayesianmgmfrm.q_matrix_validation.v1"
    @test mgmfrm_q_validation.passed
    @test mgmfrm_q_validation.dimension_labels == ["dim=1", "dim=2"]
    @test mgmfrm_q_validation.summary.fixed_q_confirmatory
    @test mgmfrm_q_validation.summary.n_cross_loading_items == 0
    @test any(row -> row.check === :duplicate_dimension_columns &&
        row.status === :passed,
        mgmfrm_q_validation.rows)
    @test any(row -> row.check === :cross_loading_policy &&
        row.status === :simple_structure,
        mgmfrm_q_validation.rows)
    @test any(row -> row.check === :dimension_facet_subgraph_coverage &&
        row.dimension_label == "dim=1" &&
        row.status === :connected_dimension_subgraph,
        mgmfrm_q_validation.rows)
    coverage_limited_data = BayesianMGMFRM._loo_refit_score_data(
        identified_data,
        identified_data,
        [1],
    )
    coverage_limited_spec = BayesianMGMFRM._replace_spec_data(
        mgmfrm_spec,
        coverage_limited_data,
    )
    coverage_limited_validation = q_matrix_validation(coverage_limited_spec)
    @test !coverage_limited_validation.passed
    @test Set(row.check for row in coverage_limited_validation.rows
        if row.severity === :error) == Set((
        :dimension_facet_subgraph_coverage,
        :fixed_q_identification_gate,
    ))
    @test BayesianMGMFRM._q_matrix_guarded_structure_passed(
        coverage_limited_validation,
    )
    invalid_q_validation = q_matrix_validation(identified_data;
        dimensions = 2,
        q_matrix = Bool[1 1; 1 1])
    @test !invalid_q_validation.passed
    @test !BayesianMGMFRM._q_matrix_guarded_structure_passed(
        invalid_q_validation,
    )
    @test any(row -> row.check === :duplicate_dimension_columns &&
        row.status === :aliased_columns &&
        row.severity === :error,
        invalid_q_validation.rows)
    @test any(row -> row.check === :positive_loading_identification &&
        row.status === :no_single_loading_anchor &&
        row.severity === :warning,
        invalid_q_validation.rows)
    blocked_cross_loading_validation = q_matrix_validation(identified_data;
        dimensions = 2,
        q_matrix = Bool[1 1; 0 1],
        cross_loading_policy = :blocked_simple_structure)
    @test !blocked_cross_loading_validation.passed
    @test any(row -> row.check === :cross_loading_policy &&
        row.status === :blocked_cross_loading &&
        row.severity === :error,
        blocked_cross_loading_validation.rows)
    invalid_q_error = argument_error_message(() -> mfrm_spec(identified_data;
        family = :mgmfrm,
        dimensions = 2,
        q_matrix = Bool[1 1; 1 1]))
    @test occursin("invalid fixed-Q MGMFRM q_matrix", invalid_q_error)
    @test occursin("failing_checks", invalid_q_error)
    labeled_mgmfrm_spec = mfrm_spec(identified_data;
        family = :mgmfrm,
        dimensions = 2,
        q_matrix,
        dimension_labels = ["writing", "analysis"])
    @test labeled_mgmfrm_spec.dimension_labels == ["writing", "analysis"]
    @test q_matrix_validation(labeled_mgmfrm_spec).dimension_labels ==
        ["writing", "analysis"]
    @test_throws ArgumentError fit(mgmfrm_spec;
        experimental = true,
        backend = :julia,
        ndraws = 1,
        warmup = 0)
    @test any(row -> row.block === :item_dimension_discrimination && row.constraint === :confirmatory_q_mask,
        constraint_table(mgmfrm_spec))
    @test any(row -> row.block === :rater_consistency && row.constraint === :geometric_mean_one,
        constraint_table(mgmfrm_spec))
    @test any(row -> row.block === :item_steps && row.constraint === :first_step_zero_sum_to_zero,
        constraint_table(mgmfrm_spec))
    mgmfrm_identification = identification_declarations(mgmfrm_spec)
    @test any(row -> row.block === :person &&
        :multidimensional_gauge in row.components,
        mgmfrm_identification)
    @test any(row -> row.block === :q_matrix &&
        row.rule === :fixed &&
        :multidimensional_gauge in row.components,
        mgmfrm_identification)
    @test any(row -> row.block === :rater_consistency &&
        row.rule === :geometric_mean_one,
        mgmfrm_identification)
    mgmfrm_manifest = model_manifest(mgmfrm_spec)
    @test mgmfrm_manifest.spec.scope === :planned_multidimensional_gmfrm
    @test mgmfrm_manifest.spec.dimension_labels == ["dim=1", "dim=2"]
    @test mgmfrm_manifest.spec.q_matrix == q_matrix
    @test mgmfrm_manifest.spec.q_matrix_validation.passed
    @test mgmfrm_manifest.spec.q_matrix_validation.summary.fixed_q_confirmatory
    @test any(row -> row.block === :q_matrix && row.rule === :fixed,
        mgmfrm_manifest.spec.identification_declarations)
    @test mgmfrm_manifest.spec.equation.family === :mgmfrm
    @test mgmfrm_manifest.spec.equation.dimension_labels == ["dim=1", "dim=2"]
    @test occursin("1.7 * alpha_r", mgmfrm_manifest.spec.equation.kernel)
    @test :item_dimension_discrimination in mgmfrm_manifest.spec.equation.required_blocks
    @test :multidimensional_ability_prior_and_gauge in
        mgmfrm_manifest.spec.equation.implementation_gaps
    mgmfrm_preview = getdesign(mgmfrm_spec; preview = true)
    @test mgmfrm_preview.spec === mgmfrm_spec
    @test mgmfrm_preview.identification[:person] === :multidimensional_location_gauge
    @test mgmfrm_preview.identification[:rater] === :sum_to_zero
    @test mgmfrm_preview.identification[:item_dimension_discrimination] === :confirmatory_q_mask
    @test mgmfrm_preview.identification[:rater_consistency] === :geometric_mean_one
    @test mgmfrm_preview.identification[:item_steps] === :first_step_zero_sum_to_zero
    mgmfrm_preview_identification = identification_declarations(mgmfrm_preview)
    q_identification = only(filter(row -> row.block === :q_matrix,
        mgmfrm_preview_identification))
    @test q_identification.rule === :fixed
    @test q_identification.n_parameters == 0
    @test isempty(q_identification.parameter_names)
    loading_identification = only(filter(row ->
        row.block === :item_dimension_discrimination,
        mgmfrm_preview_identification))
    @test :multidimensional_gauge in loading_identification.components
    @test loading_identification.n_parameters == count(q_matrix)
    @test mgmfrm_preview.parameter_names[mgmfrm_preview.blocks[:person]] == [
        "person[E1,dim=1]",
        "person[E1,dim=2]",
        "person[E2,dim=1]",
        "person[E2,dim=2]",
    ]
    @test mgmfrm_preview.parameter_names[mgmfrm_preview.blocks[:item_dimension_discrimination]] == [
        "item_dimension_discrimination[item=I1,dim=1]",
        "item_dimension_discrimination[item=I2,dim=2]",
    ]
    labeled_mgmfrm_preview = getdesign(labeled_mgmfrm_spec; preview = true)
    @test labeled_mgmfrm_preview.parameter_names[labeled_mgmfrm_preview.blocks[:person]] == [
        "person[E1,writing]",
        "person[E1,analysis]",
        "person[E2,writing]",
        "person[E2,analysis]",
    ]
    @test labeled_mgmfrm_preview.parameter_names[
        labeled_mgmfrm_preview.blocks[:item_dimension_discrimination]] == [
        "item_dimension_discrimination[item=I1,writing]",
        "item_dimension_discrimination[item=I2,analysis]",
    ]
    @test mgmfrm_preview.parameter_names[mgmfrm_preview.blocks[:rater_consistency]] == [
        "rater_consistency[rater=R1]",
        "rater_consistency[rater=R2]",
    ]
    @test mgmfrm_preview.parameter_names[mgmfrm_preview.blocks[:item_steps]] == [
        "item_step[item=I1,m=2]",
        "item_step[item=I2,m=2]",
    ]
    @test length(mgmfrm_preview.parameter_names) == 14
    mgmfrm_preview_constraints = constraint_table(mgmfrm_preview)
    item_dim_row = only(filter(row -> row.block === :item_dimension_discrimination, mgmfrm_preview_constraints))
    @test item_dim_row.dimension_labels == ("dim=1", "dim=2")
    @test item_dim_row.n_parameters == count(q_matrix)
    @test item_dim_row.parameter_names == mgmfrm_preview.parameter_names[mgmfrm_preview.blocks[:item_dimension_discrimination]]
    q_row = only(filter(row -> row.block === :q_matrix, mgmfrm_preview_constraints))
    @test q_row.dimension_labels == ("dim=1", "dim=2")
    @test q_row.n_parameters == 0
    preview_manifest = model_manifest(mgmfrm_preview)
    @test preview_manifest.object === :design
    @test preview_manifest.spec.estimation_status === :specified_only
    @test preview_manifest.design.n_parameters == length(mgmfrm_preview.parameter_names)
    @test any(row -> row.block === :item_steps && row.n_parameters == 2,
        preview_manifest.design.blocks)
    @test preview_manifest.design.raw_parameterization.family === :mgmfrm
    @test preview_manifest.design.raw_parameterization.public_fit === false
    @test preview_manifest.design.raw_parameterization.jacobian_policy === :none_raw_coordinate_density
    @test preview_manifest.design.raw_parameterization.promotion_candidate === nothing
    mgmfrm_rows = design_row_table(mgmfrm_spec; preview = true)
    @test mgmfrm_rows[1].person_parameter_indices == [1, 2]
    @test mgmfrm_rows[1].loading_dimensions == [1]
    @test mgmfrm_rows[1].item_dimension_discrimination_parameter_names == ["item_dimension_discrimination[item=I1,dim=1]"]
    @test mgmfrm_rows[1].rater_consistency_parameter_name == "rater_consistency[rater=R1]"
    @test mgmfrm_rows[2].rater_parameter_name == "rater[R2]"
    @test mgmfrm_rows[3].loading_dimensions == [2]
    @test mgmfrm_rows[3].item_dimension_discrimination_parameter_names == ["item_dimension_discrimination[item=I2,dim=2]"]
    @test isequal(mgmfrm_rows[3].threshold_parameter_names, ["item_step[item=I2,m=2]", missing])
    @test mgmfrm_rows[3].threshold_blocks == [:item_steps, :item_steps]
    @test isempty(mgmfrm_rows[3].discrimination_parameter_indices)
    @test_throws ArgumentError linear_predictor_table(mgmfrm_spec)
    mgmfrm_predictors = linear_predictor_table(mgmfrm_spec; preview = true)
    @test length(mgmfrm_predictors) == identified_data.n * length(identified_data.category_levels)
    @test mgmfrm_predictors[1].kernel === :mgmfrm_source_aligned
    @test mgmfrm_predictors[1].active_dimensions == [1]
    @test mgmfrm_predictors[1].location_multiplier == 0
    mgmfrm_row3_cat2 = only(filter(row -> row.row == 3 && row.category == 2, mgmfrm_predictors))
    @test mgmfrm_row3_cat2.observed
    @test mgmfrm_row3_cat2.location_multiplier == 2
    @test mgmfrm_row3_cat2.active_dimensions == [2]
    @test mgmfrm_row3_cat2.item_dimension_discrimination_parameter_names == ["item_dimension_discrimination[item=I2,dim=2]"]
    @test mgmfrm_row3_cat2.rater_consistency_parameter_name == "rater_consistency[rater=R1]"
    @test isequal(mgmfrm_row3_cat2.step_parameter_names, ["item_step[item=I2,m=2]", missing])
    mgmfrm_params = [
        0.2, -0.1,      # E1 dimensions
        -0.3, 0.4,      # E2 dimensions
        0.15, -0.15,    # rater severities, sum-to-zero
        -0.2, 0.1,      # item difficulties
        1.5, 0.7,       # item-dimension discriminations under q_matrix
        1.25, 0.8,      # rater consistencies, product-one
        0.3, -0.2,      # free item steps for m = 2
    ]
    mgmfrm_raw_blueprint = BayesianMGMFRM._mgmfrm_source_unconstrained_blueprint(mgmfrm_preview)
    mgmfrm_fit_ready_blueprint =
        BayesianMGMFRM._mgmfrm_fit_ready_candidate_blueprint(mgmfrm_preview)
    @test mgmfrm_raw_blueprint.n_parameters == 12
    @test mgmfrm_raw_blueprint.scope === :mgmfrm_source_aligned
    @test mgmfrm_raw_blueprint.status === :internal_source_fixture
    @test mgmfrm_raw_blueprint.compiler_stage === :source_fixture
    @test mgmfrm_raw_blueprint.fixture_only
    @test mgmfrm_fit_ready_blueprint.scope === :minimal_confirmatory_mgmfrm_candidate
    @test mgmfrm_fit_ready_blueprint.status === :internal_fit_ready_candidate
    @test mgmfrm_fit_ready_blueprint.compiler_stage === :fit_ready_candidate
    @test !mgmfrm_fit_ready_blueprint.fixture_only
    @test !mgmfrm_fit_ready_blueprint.fit_ready
    @test mgmfrm_fit_ready_blueprint.parameter_names == mgmfrm_raw_blueprint.parameter_names
    @test mgmfrm_fit_ready_blueprint.constrained_parameter_names ==
        mgmfrm_raw_blueprint.constrained_parameter_names
    @test mgmfrm_raw_blueprint.parameter_names[mgmfrm_raw_blueprint.blocks[:rater_free]] == ["raw_rater[R1]"]
    @test mgmfrm_raw_blueprint.parameter_names[mgmfrm_raw_blueprint.blocks[:log_rater_consistency_free]] ==
        ["raw_log_rater_consistency[R1]"]
    @test_throws ArgumentError fit_ready_parameter_layout(mgmfrm_spec)
    mgmfrm_layout = fit_ready_parameter_layout(mgmfrm_spec; preview = true)
    @test mgmfrm_layout.schema == "bayesianmgmfrm.fit_ready_parameter_layout.v1"
    @test mgmfrm_layout.family === :mgmfrm
    @test mgmfrm_layout.scope === :minimal_confirmatory_mgmfrm_candidate
    @test mgmfrm_layout.status === :internal_fit_ready_candidate
    @test mgmfrm_layout.parameterization === :raw_to_constrained
    @test mgmfrm_layout.experimental_public
    @test !mgmfrm_layout.public_fit
    @test !mgmfrm_layout.fit_ready
    @test mgmfrm_layout.raw_parameter_names == mgmfrm_fit_ready_blueprint.parameter_names
    @test mgmfrm_layout.constrained_parameter_names ==
        mgmfrm_fit_ready_blueprint.constrained_parameter_names
    @test any(row -> row.block === :log_item_dimension_discrimination &&
        row.parameter_names == [
            "raw_log_item_dimension_discrimination[item=I1,dim=1]",
            "raw_log_item_dimension_discrimination[item=I2,dim=2]",
        ],
        mgmfrm_layout.raw_blocks)
    @test any(row -> row.block === :item_dimension_discrimination &&
        row.parameter_names == [
            "item_dimension_discrimination[item=I1,dim=1]",
            "item_dimension_discrimination[item=I2,dim=2]",
        ],
        mgmfrm_layout.constrained_blocks)
    @test any(row -> row.raw_block === :log_rater_consistency_free &&
        row.constrained_block === :rater_consistency &&
        row.constraint === :geometric_mean_one,
        mgmfrm_layout.transforms)
    @test_throws ArgumentError domain_compilation_summary(mgmfrm_spec)
    mgmfrm_domain = domain_compilation_summary(mgmfrm_spec; preview = true)
    mgmfrm_loading_block = only(filter(row ->
        row.block === :item_dimension_discrimination &&
        row.compiled_role === :loading_block,
        mgmfrm_domain))
    @test mgmfrm_loading_block.raw_block === :log_item_dimension_discrimination
    @test mgmfrm_loading_block.constraint === :confirmatory_q_mask
    @test mgmfrm_loading_block.prior_block === :log_item_dimension_discrimination
    @test mgmfrm_loading_block.parameter_names == [
        "item_dimension_discrimination[item=I1,dim=1]",
        "item_dimension_discrimination[item=I2,dim=2]",
    ]
    mgmfrm_audit = model_surface_audit(mgmfrm_spec)
    @test model_manifest(mgmfrm_spec).spec.model_surface_audit == mgmfrm_audit
    mgmfrm_loading_audit = only(filter(row ->
        row.block === :item_dimension_discrimination &&
        row.compiled_role === :loading_block,
        mgmfrm_audit))
    @test mgmfrm_loading_audit.current_status === :specified_only
    @test mgmfrm_loading_audit.source_symbol == "alpha_il"
    @test mgmfrm_loading_audit.raw_coordinate === :log_item_dimension_discrimination
    @test mgmfrm_loading_audit.constraint === :confirmatory_q_mask
    @test mgmfrm_loading_audit.prior_scale === :log_discrimination_sd
    @test mgmfrm_loading_audit.report_label === :dimension_loading
    @test :broad_generalized_fit in mgmfrm_loading_audit.blocked_claims
    mgmfrm_loading_mask = only(filter(row ->
        row.compiled_role === :loading_mask,
        mgmfrm_domain))
    @test mgmfrm_loading_mask.domain_option === :q_matrix
    @test mgmfrm_loading_mask.block === :item_dimension_discrimination
    @test mgmfrm_loading_mask.loading_mask == q_matrix
    @test mgmfrm_loading_mask.validation_requirement === :fixed_q_matrix_validated
    @test !mgmfrm_loading_mask.fit_ready
    @test !mgmfrm_loading_mask.public_fit
    mgmfrm_scoring_domain = only(filter(row ->
        row.compiled_role === :scoring_vector,
        mgmfrm_domain))
    @test mgmfrm_scoring_domain.block === :item_steps
    @test mgmfrm_scoring_domain.parameter_names == [
        "item_step[item=I1,m=2]",
        "item_step[item=I2,m=2]",
    ]
    @test mgmfrm_scoring_domain.scoring_vector == identified_data.category_levels
    mgmfrm_raw_manifest = preview_manifest.design.raw_parameterization
    @test mgmfrm_raw_manifest.n_raw_parameters == mgmfrm_raw_blueprint.n_parameters
    @test mgmfrm_raw_manifest.raw_parameter_names == mgmfrm_raw_blueprint.parameter_names
    mgmfrm_rater_transform = only(filter(row -> row.raw_block === :rater_free,
        mgmfrm_raw_manifest.transforms))
    @test mgmfrm_rater_transform.constrained_block === :rater
    @test mgmfrm_rater_transform.transform === :sum_to_zero_last
    @test mgmfrm_rater_transform.raw_parameter_names == ["raw_rater[R1]"]
    @test mgmfrm_rater_transform.constrained_parameter_names == ["rater[R1]", "rater[R2]"]
    mgmfrm_consistency_transform = only(filter(row -> row.raw_block === :log_rater_consistency_free,
        mgmfrm_raw_manifest.transforms))
    @test mgmfrm_consistency_transform.transform === :geometric_mean_one_log_last
    @test mgmfrm_consistency_transform.constrained_block === :rater_consistency
    @test mgmfrm_consistency_transform.prior_block === :log_rater_consistency
    @test mgmfrm_raw_manifest.promotion_candidate === nothing
    mgmfrm_confirmatory_candidate = mgmfrm_raw_manifest.confirmatory_candidate
    @test mgmfrm_confirmatory_candidate.schema ==
        "bayesianmgmfrm.mgmfrm_confirmatory_candidate.v1"
    @test mgmfrm_confirmatory_candidate.family === :mgmfrm
    @test mgmfrm_confirmatory_candidate.scope === :minimal_confirmatory_mgmfrm_candidate
    @test mgmfrm_confirmatory_candidate.status === :internal_fit_ready_candidate
    @test mgmfrm_confirmatory_candidate.public_fit
    @test mgmfrm_confirmatory_candidate.experimental_public
    @test mgmfrm_confirmatory_candidate.fit_ready
    @test !mgmfrm_confirmatory_candidate.fixture_only
    @test !mgmfrm_confirmatory_candidate.source_fixture_only
    @test mgmfrm_confirmatory_candidate.compiler_stage === :fit_ready_candidate
    @test mgmfrm_confirmatory_candidate.source_oracle === :mgmfrm_source_aligned
    @test mgmfrm_confirmatory_candidate.fit_ready_transform_ready
    @test mgmfrm_confirmatory_candidate.fit_ready_pointwise_oracle_ready
    @test mgmfrm_confirmatory_candidate.dimensions == 2
    @test mgmfrm_confirmatory_candidate.q_matrix == q_matrix
    @test mgmfrm_confirmatory_candidate.latent_correlation === :identity_fixed
    @test mgmfrm_confirmatory_candidate.ability_location === :zero_by_dimension
    @test mgmfrm_confirmatory_candidate.ability_scale === :unit_variance_by_dimension
    @test mgmfrm_confirmatory_candidate.source_scale == 1.7
    @test mgmfrm_confirmatory_candidate.interpreted_loading_sign === :positive
    @test mgmfrm_confirmatory_candidate.raw_parameter_names ==
        mgmfrm_raw_blueprint.parameter_names
    @test mgmfrm_confirmatory_candidate.constrained_parameter_names ==
        mgmfrm_preview.parameter_names
    mgmfrm_raw_prior_controls =
        mgmfrm_confirmatory_candidate.raw_prior_control_manifest
    @test mgmfrm_raw_prior_controls.schema ==
        "bayesianmgmfrm.generalized_raw_prior_control_manifest.v1"
    @test mgmfrm_raw_prior_controls.family === :mgmfrm
    @test mgmfrm_raw_prior_controls.scope === :minimal_confirmatory_mgmfrm_candidate
    @test mgmfrm_raw_prior_controls.n_rows == 7
    @test mgmfrm_raw_prior_controls.summary.raw_rater_consistency_control_recorded
    @test mgmfrm_raw_prior_controls.summary.item_discrimination_source_control_recorded
    @test !mgmfrm_raw_prior_controls.summary.direct_scale_generalized_priors_enabled
    @test any(row -> row.raw_block === :log_item_dimension_discrimination &&
        row.constrained_block === :item_dimension_discrimination &&
        row.scale_parameter === :log_discrimination_sd &&
        row.public_surface_role === :fixed_q_loading_core,
        mgmfrm_raw_prior_controls.rows)
    @test any(row -> row.raw_block === :log_rater_consistency_free &&
        row.constrained_block === :rater_consistency &&
        row.scale_parameter === :log_consistency_sd &&
        row.public_surface_role === :fixed_q_rater_consistency_core,
        mgmfrm_raw_prior_controls.rows)
    @test any(row -> row.constrained_block ===
            :direct_scale_generalized_priors &&
        row.status === :blocked &&
        row.jacobian_policy === :requires_future_log_jacobian_policy,
        mgmfrm_raw_prior_controls.rows)
    @test any(row -> row.gauge === :q_matrix &&
        row.status === :fixed &&
        row.value == q_matrix,
        mgmfrm_confirmatory_candidate.gauge_rows)
    @test any(row -> row.gauge === :latent_correlation &&
        row.value === :identity,
        mgmfrm_confirmatory_candidate.gauge_rows)
    @test any(row -> row.block === :item_dimension_discrimination &&
        row.rule === :positive_interpreted_q_masked_loadings,
        mgmfrm_confirmatory_candidate.sign_positive_rules)
    @test any(row -> row.evidence === :bridgestan_source_oracle &&
        row.status === :done,
        mgmfrm_confirmatory_candidate.evidence_rows)
    @test any(row -> row.evidence === :fit_ready_bridge_pointwise_oracle &&
        row.status === :done,
        mgmfrm_confirmatory_candidate.evidence_rows)
    @test any(row -> row.evidence === :fit_ready_transform_manifest &&
        row.status === :done,
        mgmfrm_confirmatory_candidate.evidence_rows)
    @test any(row -> row.evidence === :fit_ready_pointwise_fixture &&
        row.status === :done &&
        row.artifact === :mgmfrm_confirmatory_candidate_pointwise_fixture,
        mgmfrm_confirmatory_candidate.evidence_rows)
    @test !any(row -> row.blocker === :fit_ready_mgmfrm_bridge_oracle_missing,
        mgmfrm_confirmatory_candidate.blocker_rows)
    @test !any(row -> row.blocker === :mgmfrm_sampler_diagnostics_missing,
        mgmfrm_confirmatory_candidate.blocker_rows)
    @test !any(row -> row.blocker === :mgmfrm_recovery_smoke_missing,
        mgmfrm_confirmatory_candidate.blocker_rows)
    @test isempty(mgmfrm_confirmatory_candidate.blocker_rows)
    @test any(row -> row.gate === :confirmatory_q_mask &&
        row.status === :done,
        mgmfrm_confirmatory_candidate.candidate_gates)
    @test any(row -> row.gate === :fit_ready_raw_transform_manifest &&
        row.status === :done,
        mgmfrm_confirmatory_candidate.candidate_gates)
    @test any(row -> row.gate === :fit_ready_pointwise_fixture &&
        row.status === :done &&
        row.evidence === :mgmfrm_confirmatory_candidate_pointwise_fixture,
        mgmfrm_confirmatory_candidate.candidate_gates)
    @test any(row -> row.gate === :fit_ready_bridge_pointwise_oracle &&
        row.status === :done,
        mgmfrm_confirmatory_candidate.candidate_gates)
    @test any(row -> row.gate === :sampler_diagnostic_study &&
        row.status === :done,
        mgmfrm_confirmatory_candidate.candidate_gates)
    @test any(row -> row.gate === :recovery_smoke_study &&
        row.status === :done,
        mgmfrm_confirmatory_candidate.candidate_gates)
    @test any(row -> row.gate === :public_fit_api &&
        row.status === :done &&
        row.evidence === :mgmfrm_experimental_public_api_decision,
        mgmfrm_confirmatory_candidate.candidate_gates)
    @test mgmfrm_confirmatory_candidate.summary.candidate_frozen
    @test mgmfrm_confirmatory_candidate.summary.fit_allowed
    @test mgmfrm_confirmatory_candidate.summary.n_evidence_done >= 7
    @test mgmfrm_confirmatory_candidate.summary.n_evidence_pending == 0
    @test mgmfrm_confirmatory_candidate.summary.next_gate ===
        :manual_publication_or_registration_by_user_only
    mgmfrm_experimental_decision =
        mgmfrm_confirmatory_candidate.experimental_public_api_decision
    @test mgmfrm_experimental_decision.schema ==
        "bayesianmgmfrm.mgmfrm_experimental_public_api_decision.v1"
    @test mgmfrm_experimental_decision.family === :mgmfrm
    @test mgmfrm_experimental_decision.scope === :minimal_confirmatory_mgmfrm_candidate
    @test mgmfrm_experimental_decision.status === :experimental_public
    @test mgmfrm_experimental_decision.decision === :enable_guarded_experimental
    @test mgmfrm_experimental_decision.public_fit
    @test mgmfrm_experimental_decision.experimental_public
    @test mgmfrm_experimental_decision.fit_ready
    @test mgmfrm_experimental_decision.proposed_entrypoint ==
        "BayesianMGMFRM.Experimental.fit(spec)"
    @test mgmfrm_experimental_decision.legacy_entrypoint ==
        "BayesianMGMFRM.fit(spec; experimental = true)"
    @test mgmfrm_experimental_decision.public_target_label ===
        :guarded_confirmatory_mgmfrm_logdensity
    @test mgmfrm_experimental_decision.public_target_description ==
        "guarded fixed-Q confirmatory MGMFRM log density"
    @test mgmfrm_experimental_decision.internal_target_constructor ===
        :_mgmfrm_guarded_local_fit_logdensity
    @test mgmfrm_experimental_decision.internal_sampler_diagnostic_constructor ===
        :_mgmfrm_guarded_local_fit_sampler_diagnostics
    @test mgmfrm_experimental_decision.guarded_local_entrypoint ===
        :_fit_guarded_mgmfrm
    @test mgmfrm_experimental_decision.guarded_local_fit_target_constructor ===
        :_mgmfrm_guarded_local_fit_logdensity
    @test mgmfrm_experimental_decision.guarded_local_fit_sampler_diagnostic_constructor ===
        :_mgmfrm_guarded_local_fit_sampler_diagnostics
    @test mgmfrm_experimental_decision.guarded_local_fit_artifact_schema ==
        "bayesianmgmfrm.mgmfrm_experimental_fit_artifact.v1"
    @test mgmfrm_experimental_decision.experimental_fit_artifact_schema ==
        "bayesianmgmfrm.mgmfrm_experimental_fit_artifact.v1"
    @test mgmfrm_experimental_decision.candidate_chain_study_artifact ==
        "test/fixtures/mgmfrm_candidate_chain_study.json"
    @test mgmfrm_experimental_decision.recovery_smoke_artifact ==
        "test/fixtures/mgmfrm_recovery_smoke.json"
    @test mgmfrm_experimental_decision.baseline_comparison_artifact ==
        "test/fixtures/mgmfrm_baseline_comparison.json"
    @test mgmfrm_experimental_decision.sparse_recovery_grid_artifact ==
        "test/fixtures/mgmfrm_sparse_recovery_grid.json"
    @test mgmfrm_experimental_decision.guarded_fit_method_wiring_artifact ==
        "test/fixtures/mgmfrm_guarded_fit_method_wiring.json"
    @test mgmfrm_experimental_decision.guarded_fit_validation_grid_artifact ==
        "test/fixtures/mgmfrm_guarded_fit_validation_grid.json"
    @test mgmfrm_experimental_decision.guarded_fit_api_dry_run_artifact ==
        "test/fixtures/mgmfrm_guarded_fit_api_dry_run.json"
    @test mgmfrm_experimental_decision.guarded_fit_public_exposure_review_artifact ==
        "test/fixtures/mgmfrm_guarded_fit_public_exposure_review.json"
    @test mgmfrm_experimental_decision.dff_estimand_validation_grid_artifact ==
        "test/fixtures/gmfrm_dff_estimand_validation_grid.json"
    @test mgmfrm_experimental_decision.manuscript_scale_simulation_grid_artifact ==
        "test/fixtures/gmfrm_manuscript_scale_simulation_grid.json"
    @test mgmfrm_experimental_decision.full_paper_reproduction_archive_artifact ==
        "test/fixtures/gmfrm_full_paper_reproduction_archive.json"
    @test mgmfrm_experimental_decision.caveat_docs_artifact ==
        "docs/src/fitting.md#guarded-generalized-model-caveats"
    mgmfrm_prior_policy = mgmfrm_experimental_decision.prior_jacobian_policy
    @test mgmfrm_prior_policy.schema ==
        "bayesianmgmfrm.generalized_raw_prior_jacobian_policy.v1"
    @test mgmfrm_prior_policy.family === :mgmfrm
    @test mgmfrm_prior_policy.scope === :minimal_confirmatory_mgmfrm_candidate
    @test mgmfrm_prior_policy.status === :policy_recorded
    @test mgmfrm_prior_policy.prior_policy === :independent_normal_raw_coordinates
    @test !mgmfrm_prior_policy.direct_scale_priors
    @test mgmfrm_prior_policy.jacobian_policy === :none_raw_coordinate_density
    mgmfrm_decision_raw_prior_controls =
        mgmfrm_experimental_decision.raw_prior_control_manifest
    @test mgmfrm_decision_raw_prior_controls.schema ==
        "bayesianmgmfrm.generalized_raw_prior_control_manifest.v1"
    @test mgmfrm_decision_raw_prior_controls.public_fit
    @test mgmfrm_decision_raw_prior_controls.experimental_public
    @test any(row -> row.raw_block === :log_item_dimension_discrimination &&
        row.scale_parameter === :log_discrimination_sd,
        mgmfrm_decision_raw_prior_controls.rows)
    @test any(row -> row.raw_block === :log_rater_consistency_free &&
        row.scale_parameter === :log_consistency_sd,
        mgmfrm_decision_raw_prior_controls.rows)
    mgmfrm_fit_artifact_contract =
        mgmfrm_experimental_decision.fit_artifact_contract
    @test mgmfrm_fit_artifact_contract.schema ==
        "bayesianmgmfrm.experimental_generalized_fit_artifact_contract.v1"
    @test mgmfrm_fit_artifact_contract.family === :mgmfrm
    @test mgmfrm_fit_artifact_contract.scope === :minimal_confirmatory_mgmfrm_candidate
    @test mgmfrm_fit_artifact_contract.status === :contract_recorded
    @test mgmfrm_fit_artifact_contract.public_fit
    @test mgmfrm_fit_artifact_contract.experimental_public
    @test mgmfrm_fit_artifact_contract.artifact_kind ===
        :experimental_generalized_fit_artifact
    @test mgmfrm_fit_artifact_contract.summary.enables_public_fit
    @test any(row -> row.field === :q_matrix &&
        row.status === :required,
        mgmfrm_fit_artifact_contract.required_fields)
    @test any(row -> row.field === :public_target_label &&
        row.status === :required,
        mgmfrm_fit_artifact_contract.required_fields)
    @test any(row -> row.field === :internal_target_constructor &&
        row.status === :required,
        mgmfrm_fit_artifact_contract.required_fields)
    @test any(row -> row.field === :parameter_layout &&
        row.status === :required,
        mgmfrm_fit_artifact_contract.required_fields)
    @test any(row -> row.field === :raw_prior_control_manifest &&
        row.status === :required,
        mgmfrm_fit_artifact_contract.required_fields)
    @test any(row -> row.field === :raw_posterior_row_schema &&
        row.status === :required,
        mgmfrm_fit_artifact_contract.required_fields)
    @test any(row -> row.field === :direct_posterior_row_schema &&
        row.status === :required,
        mgmfrm_fit_artifact_contract.required_fields)
    @test any(row -> row.field === :latent_correlation &&
        row.status === :required,
        mgmfrm_fit_artifact_contract.required_fields)
    @test any(row -> row.field === :initialization_policy &&
        row.status === :required,
        mgmfrm_fit_artifact_contract.required_fields)
    @test any(row -> row.field === :initialization_rows &&
        row.status === :required,
        mgmfrm_fit_artifact_contract.required_fields)
    @test any(row -> row.field === :fixed_q_invariance_rows &&
        row.status === :required,
        mgmfrm_fit_artifact_contract.required_fields)
    @test any(row -> row.artifact === :bridge_oracle &&
        row.value == "test/fixtures/source_mgmfrm_bridge_logdensity.json#confirmatory_candidate",
        mgmfrm_fit_artifact_contract.provenance_rows)
    @test any(row -> row.option === :q_matrix &&
        row.value === :fixed_confirmatory,
        mgmfrm_experimental_decision.accepted_candidate_options)
    @test any(row -> row.option === :entrypoint &&
        row.value == "BayesianMGMFRM.Experimental.fit(spec)" &&
        row.status === :enabled_guarded_experimental,
        mgmfrm_experimental_decision.accepted_candidate_options)
    @test any(row -> row.option === :legacy_entrypoint &&
        row.value == "BayesianMGMFRM.fit(spec; experimental = true)" &&
        row.status === :compatibility_only,
        mgmfrm_experimental_decision.accepted_candidate_options)
    @test any(row -> row.option === :latent_correlation &&
        row.value === :free &&
        row.status === :blocked,
        mgmfrm_experimental_decision.rejected_public_options)
    @test any(row -> row.option === :sparse_design_claims &&
        row.value === :enabled &&
        row.status === :blocked_broader_claim &&
        row.blocker === :broader_sparse_mgmfrm_claim_scope_not_promoted,
        mgmfrm_experimental_decision.rejected_public_options)
    @test any(row -> row.option === :baseline_comparison &&
        row.value === :mfrm_rsm_pcm_comparison &&
        row.status === :evidence_only_for_guarded_fit &&
        row.blocker === :model_weight_or_superiority_claim_not_promoted,
        mgmfrm_experimental_decision.rejected_public_options)
    @test mgmfrm_experimental_decision.guarded_fit_public_exposure_review_interpretation.status ===
        :review_recorded
    @test mgmfrm_experimental_decision.guarded_fit_public_exposure_review_interpretation.review_target ===
        :confirmatory_mgmfrm_guarded_fit_public_exposure
    @test mgmfrm_experimental_decision.guarded_fit_public_exposure_review_interpretation.public_exposure_support ===
        :supports_fixed_q_confirmatory_mgmfrm_experimental_fit
    @test mgmfrm_experimental_decision.guarded_fit_public_exposure_review_interpretation.required_followup ===
        :satisfied_by_prediction_target_and_model_weight_policy
    @test mgmfrm_experimental_decision.prediction_target_and_model_weight_policy_artifact ==
        "test/fixtures/gmfrm_prediction_target_and_model_weight_policy.json"
    @test mgmfrm_experimental_decision.prediction_target_and_model_weight_policy_interpretation.status ===
        :policy_recorded
    @test mgmfrm_experimental_decision.prediction_target_and_model_weight_policy_interpretation.public_exposure_support ===
        :guarded_confirmatory_mgmfrm_fit_enabled_no_weight_claims
    @test mgmfrm_experimental_decision.prediction_target_and_model_weight_policy_interpretation.required_followup ===
        :manual_publication_or_registration_by_user_only
    @test any(row -> row.evidence === :bridgestan_fit_ready_oracle &&
        row.status === :done,
        mgmfrm_experimental_decision.evidence_rows)
    @test any(row -> row.evidence === :candidate_chain_study &&
        row.status === :done,
        mgmfrm_experimental_decision.evidence_rows)
    @test any(row -> row.evidence === :recovery_smoke_study &&
        row.status === :done,
        mgmfrm_experimental_decision.evidence_rows)
    @test any(row -> row.evidence === :baseline_comparison &&
        row.status === :done &&
        row.artifact == "test/fixtures/mgmfrm_baseline_comparison.json",
        mgmfrm_experimental_decision.evidence_rows)
    @test any(row -> row.evidence === :sparse_recovery_grid &&
        row.status === :done &&
        row.artifact == "test/fixtures/mgmfrm_sparse_recovery_grid.json",
        mgmfrm_experimental_decision.evidence_rows)
    @test any(row -> row.evidence === :guarded_fit_method_wiring &&
        row.status === :done &&
        row.artifact == "test/fixtures/mgmfrm_guarded_fit_method_wiring.json",
        mgmfrm_experimental_decision.evidence_rows)
    @test any(row -> row.evidence === :guarded_fit_validation_grid &&
        row.status === :done &&
        row.artifact == "test/fixtures/mgmfrm_guarded_fit_validation_grid.json",
        mgmfrm_experimental_decision.evidence_rows)
    @test any(row -> row.evidence === :guarded_fit_api_dry_run &&
        row.status === :done &&
        row.artifact == "test/fixtures/mgmfrm_guarded_fit_api_dry_run.json",
        mgmfrm_experimental_decision.evidence_rows)
    @test any(row -> row.evidence === :guarded_local_fit_entrypoint &&
        row.status === :done &&
        row.artifact === :_fit_guarded_mgmfrm,
        mgmfrm_experimental_decision.evidence_rows)
    @test any(row -> row.evidence === :guarded_fit_public_exposure_review &&
        row.status === :done &&
        row.artifact ==
            "test/fixtures/mgmfrm_guarded_fit_public_exposure_review.json",
        mgmfrm_experimental_decision.evidence_rows)
    @test any(row -> row.evidence === :prediction_target_and_model_weight_policy &&
        row.status === :done &&
        row.artifact ==
            "test/fixtures/gmfrm_prediction_target_and_model_weight_policy.json",
        mgmfrm_experimental_decision.evidence_rows)
    @test any(row -> row.evidence === :dff_estimand_validation_grid &&
        row.status === :done &&
        row.artifact == "test/fixtures/gmfrm_dff_estimand_validation_grid.json",
        mgmfrm_experimental_decision.evidence_rows)
    @test any(row -> row.evidence === :manuscript_scale_simulation_grid &&
        row.status === :done &&
        row.artifact ==
            "test/fixtures/gmfrm_manuscript_scale_simulation_grid.json",
        mgmfrm_experimental_decision.evidence_rows)
    @test any(row -> row.evidence === :full_paper_reproduction_archive &&
        row.status === :done &&
        row.artifact ==
            "test/fixtures/gmfrm_full_paper_reproduction_archive.json",
        mgmfrm_experimental_decision.evidence_rows)
    @test any(row -> row.evidence === :public_caveat_docs &&
        row.status === :done &&
        row.artifact == "docs/src/fitting.md#guarded-generalized-model-caveats",
        mgmfrm_experimental_decision.evidence_rows)
    @test any(row -> row.evidence === :fit_artifact_manifest_for_experimental_public &&
        row.status === :done &&
        row.artifact === :experimental_public_fit_artifact_contract,
        mgmfrm_experimental_decision.evidence_rows)
    @test any(row -> row.evidence === :direct_prior_jacobian_policy &&
        row.status === :done &&
        row.artifact === :generalized_raw_prior_jacobian_policy,
        mgmfrm_experimental_decision.evidence_rows)
    @test any(row -> row.evidence === :raw_prior_control_manifest &&
        row.status === :done &&
        row.artifact === :generalized_raw_prior_control_manifest,
        mgmfrm_experimental_decision.evidence_rows)
    @test !any(row -> row.blocker === :public_fit_artifact_contract_missing,
        mgmfrm_experimental_decision.blocker_rows)
    @test !any(row -> row.blocker === :direct_prior_jacobian_policy_pending,
        mgmfrm_experimental_decision.blocker_rows)
    @test !any(row -> row.blocker === :public_caveat_docs_missing,
        mgmfrm_experimental_decision.blocker_rows)
    @test !any(row -> row.blocker === :baseline_comparison_missing,
        mgmfrm_experimental_decision.blocker_rows)
    @test !any(row -> row.blocker === :sparse_recovery_grid_missing,
        mgmfrm_experimental_decision.blocker_rows)
    @test !any(row -> row.blocker === :dff_estimand_and_validation_evidence_missing,
        mgmfrm_experimental_decision.blocker_rows)
    @test !any(row -> row.blocker === :manuscript_scale_simulation_grid_missing,
        mgmfrm_experimental_decision.blocker_rows)
    @test !any(row -> row.blocker === :full_paper_reproduction_archive_missing,
        mgmfrm_experimental_decision.blocker_rows)
    @test !any(row -> row.blocker === :manual_public_scope_review_for_mgmfrm_fit_missing,
        mgmfrm_experimental_decision.blocker_rows)
    @test mgmfrm_experimental_decision.summary.n_evidence_done >= 17
    @test mgmfrm_experimental_decision.summary.n_evidence_pending == 0
    @test mgmfrm_experimental_decision.summary.n_evidence_blocked == 0
    @test mgmfrm_experimental_decision.summary.fit_allowed
    @test mgmfrm_experimental_decision.summary.canonical_namespace_enabled
    @test mgmfrm_experimental_decision.summary.experimental_keyword_enabled
    @test mgmfrm_experimental_decision.summary.legacy_keyword_status ===
        :compatibility_only
    @test mgmfrm_experimental_decision.summary.n_blockers == 0
    @test mgmfrm_experimental_decision.summary.next_gate ===
        :manual_publication_or_registration_by_user_only
    mgmfrm_raw_params = [
        0.2, -0.1,
        -0.3, 0.4,
        0.15,
        -0.2, 0.1,
        log(1.5), log(0.7),
        log(1.25),
        0.3, -0.2,
    ]
    @test BayesianMGMFRM._mgmfrm_source_constrained_params_from_unconstrained(
        mgmfrm_preview,
        mgmfrm_raw_params,
    ) ≈ mgmfrm_params
    @test_throws ArgumentError BayesianMGMFRM._mgmfrm_source_constrained_params_from_unconstrained(
        mgmfrm_preview,
        mgmfrm_raw_params[1:end-1],
    )
    for block in (:log_item_dimension_discrimination, :log_rater_consistency_free),
            boundary_value in (800.0, -1000.0)
        boundary_raw_params = copy(mgmfrm_raw_params)
        boundary_raw_params[first(mgmfrm_raw_blueprint.blocks[block])] = boundary_value
        @test_throws ArgumentError BayesianMGMFRM._mgmfrm_source_constrained_params_from_unconstrained(
            mgmfrm_preview,
            boundary_raw_params,
        )
    end
    mgmfrm_source_values = BayesianMGMFRM._mgmfrm_source_fixture_values(mgmfrm_preview, mgmfrm_params)
    mgmfrm_source_pointwise =
        BayesianMGMFRM._mgmfrm_source_pointwise_loglikelihood(mgmfrm_preview, mgmfrm_params)
    mgmfrm_direct_pointwise_fixture =
        BayesianMGMFRM._mgmfrm_confirmatory_candidate_pointwise_fixture(
            mgmfrm_preview,
            mgmfrm_params,
        )
    @test mgmfrm_direct_pointwise_fixture.schema ==
        "bayesianmgmfrm.mgmfrm_confirmatory_candidate_pointwise_fixture.v1"
    @test mgmfrm_direct_pointwise_fixture.summary.passed
    @test mgmfrm_direct_pointwise_fixture.summary.flag === :ok
    @test mgmfrm_direct_pointwise_fixture.scope ===
        :minimal_confirmatory_mgmfrm_candidate
    @test mgmfrm_direct_pointwise_fixture.density_space === :constrained_direct
    @test mgmfrm_direct_pointwise_fixture.q_matrix == q_matrix
    @test mgmfrm_direct_pointwise_fixture.latent_correlation === :identity_fixed
    @test mgmfrm_direct_pointwise_fixture.parameter_layout.scope ===
        :minimal_confirmatory_mgmfrm_candidate
    @test mgmfrm_direct_pointwise_fixture.parameter_layout.constrained_parameter_names ==
        mgmfrm_direct_pointwise_fixture.parameter_names
    @test mgmfrm_direct_pointwise_fixture.parameter_names ==
        mgmfrm_preview.parameter_names
    @test mgmfrm_direct_pointwise_fixture.parameter_values ≈ mgmfrm_params
    @test mgmfrm_direct_pointwise_fixture.summary.n_rows == length(mgmfrm_predictors)
    @test mgmfrm_direct_pointwise_fixture.summary.n_pointwise == identified_data.n
    @test mgmfrm_direct_pointwise_fixture.pointwise_loglikelihood ≈
        mgmfrm_source_pointwise
    @test mgmfrm_direct_pointwise_fixture.loglikelihood ≈
        sum(mgmfrm_source_pointwise)
    @test isequal(mgmfrm_direct_pointwise_fixture.rows, mgmfrm_source_values)
    @test all(row -> row.passed, mgmfrm_direct_pointwise_fixture.constraint_rows)
    @test only(filter(row -> row.block === :rater_consistency,
        mgmfrm_direct_pointwise_fixture.blocks)).values ≈ [1.25, 0.8]
    @test BayesianMGMFRM._mgmfrm_source_pointwise_loglikelihood_from_unconstrained(
        mgmfrm_preview,
        mgmfrm_raw_params,
    ) ≈ mgmfrm_source_pointwise
    @test BayesianMGMFRM._mgmfrm_source_loglikelihood_from_unconstrained(
        mgmfrm_preview,
        mgmfrm_raw_params,
    ) ≈ sum(mgmfrm_source_pointwise)
    @test_throws ArgumentError BayesianMGMFRM._mgmfrm_source_pointwise_loglikelihood_from_unconstrained(
        mgmfrm_preview,
        mgmfrm_raw_params[1:end-1],
    )
    mgmfrm_target = BayesianMGMFRM._source_fixture_logdensity(mgmfrm_preview; prior = source_prior)
    mgmfrm_spec_target = BayesianMGMFRM._source_fixture_logdensity(mgmfrm_spec; prior = source_prior)
    @test_throws ArgumentError BayesianMGMFRM._gmfrm_promotion_candidate_logdensity(mgmfrm_preview)
    @test_throws ArgumentError BayesianMGMFRM._gmfrm_fit_ready_candidate_blueprint(mgmfrm_preview)
    @test LogDensityProblems.dimension(mgmfrm_target) == mgmfrm_raw_blueprint.n_parameters
    @test LogDensityProblems.dimension(mgmfrm_spec_target) == mgmfrm_raw_blueprint.n_parameters
    @test LogDensityProblems.capabilities(typeof(mgmfrm_target)) == LogDensityProblems.LogDensityOrder{0}()
    @test initial_params(mgmfrm_target; value = -0.05) == fill(-0.05, mgmfrm_raw_blueprint.n_parameters)
    @test occursin("SourceFixtureLogDensity(mgmfrm", sprint(show, mgmfrm_target))
    mgmfrm_prior_sds = [
        1.1, 1.1, 1.1, 1.1,
        1.2,
        1.3, 1.3,
        1.4, 1.4,
        1.5,
        1.6, 1.6,
    ]
    mgmfrm_expected_prior = sum(test_normal_logpdf(x, sd)
        for (x, sd) in zip(mgmfrm_raw_params, mgmfrm_prior_sds))
    @test BayesianMGMFRM._source_fixture_logprior(mgmfrm_target, mgmfrm_raw_params) ≈
        mgmfrm_expected_prior
    @test BayesianMGMFRM._source_fixture_loglikelihood(mgmfrm_target, mgmfrm_raw_params) ≈
        sum(mgmfrm_source_pointwise)
    @test LogDensityProblems.logdensity(mgmfrm_target, mgmfrm_raw_params) ≈
        sum(mgmfrm_source_pointwise) + mgmfrm_expected_prior
    @test LogDensityProblems.logdensity(mgmfrm_spec_target, mgmfrm_raw_params) ≈
        LogDensityProblems.logdensity(mgmfrm_target, mgmfrm_raw_params)
    mgmfrm_logp = x -> LogDensityProblems.logdensity(mgmfrm_target, x)
    mgmfrm_forward_gradient = check_forwarddiff_gradient(mgmfrm_logp, mgmfrm_raw_params)
    @test length(mgmfrm_forward_gradient) == mgmfrm_raw_blueprint.n_parameters
    mgmfrm_hmc_samples, mgmfrm_hmc_stats = check_advancedhmc_smoke(
        mgmfrm_target,
        mgmfrm_raw_params;
        seed = 20260620,
    )
    @test length(mgmfrm_hmc_samples) == length(mgmfrm_hmc_stats) == 2
    mgmfrm_guarded_target =
        BayesianMGMFRM._mgmfrm_guarded_local_fit_logdensity(
            mgmfrm_preview;
            prior = source_prior,
        )
    @test LogDensityProblems.dimension(mgmfrm_guarded_target) ==
        mgmfrm_raw_blueprint.n_parameters
    @test LogDensityProblems.logdensity(mgmfrm_guarded_target, mgmfrm_raw_params) ≈
        LogDensityProblems.logdensity(mgmfrm_target, mgmfrm_raw_params)
    @test occursin("MGMFRMGuardedLocalFitLogDensity",
        sprint(show, mgmfrm_guarded_target))
    mgmfrm_raw_pointwise_fixture =
        BayesianMGMFRM._mgmfrm_confirmatory_candidate_pointwise_fixture(
            mgmfrm_guarded_target,
            mgmfrm_raw_params,
        )
    @test mgmfrm_raw_pointwise_fixture.summary.passed
    @test mgmfrm_raw_pointwise_fixture.raw_parameter_names ==
        mgmfrm_raw_blueprint.parameter_names
    @test mgmfrm_raw_pointwise_fixture.parameter_layout.raw_parameter_names ==
        mgmfrm_raw_pointwise_fixture.raw_parameter_names
    @test mgmfrm_raw_pointwise_fixture.raw_parameter_values ≈ mgmfrm_raw_params
    @test mgmfrm_raw_pointwise_fixture.parameter_values ≈ mgmfrm_params
    @test mgmfrm_raw_pointwise_fixture.pointwise_loglikelihood ≈
        mgmfrm_source_pointwise
    mgmfrm_default_initial =
        BayesianMGMFRM._guarded_mgmfrm_initial(mgmfrm_guarded_target, nothing)
    @test mgmfrm_default_initial == initial_params(mgmfrm_guarded_target)
    mgmfrm_default_initial_direct =
        BayesianMGMFRM._mgmfrm_source_constrained_params_from_unconstrained(
            mgmfrm_preview,
            mgmfrm_default_initial,
        )
    mgmfrm_default_initial_policy =
        BayesianMGMFRM._mgmfrm_initialization_policy(
            mgmfrm_guarded_target,
            mgmfrm_default_initial,
            mgmfrm_default_initial_direct,
            LogDensityProblems.logdensity(
                mgmfrm_guarded_target,
                mgmfrm_default_initial,
            ),
            (; init_jitter = 0.0);
            initial_source = :default_zero_raw,
        )
    @test mgmfrm_default_initial_policy.fallback_used
    @test mgmfrm_default_initial_policy.status === :default_zero_fallback
    @test mgmfrm_default_initial_policy.finite_initial_logdensity
    @test isempty(BayesianMGMFRM._mgmfrm_initialization_rows(nothing))
    mgmfrm_nonfinite_initial_policy =
        BayesianMGMFRM._mgmfrm_initialization_policy(
            mgmfrm_guarded_target,
            fill(Inf, length(mgmfrm_default_initial)),
            fill(Inf, length(mgmfrm_default_initial_direct)),
            Inf,
            (; init_jitter = 0.01);
            initial_source = :sampler_raw_initial_argument,
        )
    mgmfrm_nonfinite_initial_rows =
        BayesianMGMFRM._mgmfrm_initialization_rows(
            mgmfrm_nonfinite_initial_policy,
        )
    @test !mgmfrm_nonfinite_initial_policy.finite_initial_raw_values
    @test !mgmfrm_nonfinite_initial_policy.finite_initial_direct_values
    @test !mgmfrm_nonfinite_initial_policy.finite_initial_logdensity
    @test any(row -> row.policy === :initial_raw_vector &&
        row.status === :raw_initial_argument &&
        !row.passed,
        mgmfrm_nonfinite_initial_rows)
    @test any(row -> row.policy === :initial_logdensity &&
        row.status === :nonfinite &&
        !row.passed,
        mgmfrm_nonfinite_initial_rows)
    @test any(row -> row.policy === :initial_direct_transform &&
        row.status === :nonfinite &&
        !row.passed,
        mgmfrm_nonfinite_initial_rows)
    @test any(row -> row.policy === :per_chain_initialization &&
        row.status === :jittered &&
        row.passed,
        mgmfrm_nonfinite_initial_rows)
    mgmfrm_unrecorded_invariance_rows =
        BayesianMGMFRM._mgmfrm_fixed_q_invariance_rows(mgmfrm_preview)
    @test any(row -> row.policy === :interpreted_loading_values &&
        row.status === :not_recorded &&
        ismissing(row.value) &&
        ismissing(row.passed),
        mgmfrm_unrecorded_invariance_rows)
    @test any(row -> row.policy === :direct_constraints &&
        row.status === :not_recorded &&
        ismissing(row.value) &&
        ismissing(row.passed),
        mgmfrm_unrecorded_invariance_rows)
    mgmfrm_failed_surface = (;
        direct_constraint_rows = [
            (constraint = :item_dimension_discrimination_positive,
                block = :item_dimension_discrimination,
                n_failed = 2,
                passed = false),
            (constraint = :rater_consistency_positive,
                block = :rater_consistency,
                n_failed = 1,
                passed = false),
        ],
        summary = (; n_failed_direct_constraints = 3),
    )
    mgmfrm_failed_invariance_rows =
        BayesianMGMFRM._mgmfrm_fixed_q_invariance_rows(
            mgmfrm_preview,
            mgmfrm_failed_surface,
        )
    @test any(row -> row.policy === :interpreted_loading_values &&
        row.status === :failed &&
        row.value == 2 &&
        row.passed == false,
        mgmfrm_failed_invariance_rows)
    @test any(row -> row.policy === :direct_constraints &&
        row.status === :failed &&
        row.value == 3 &&
        row.passed == false,
        mgmfrm_failed_invariance_rows)
    mgmfrm_guarded_fit =
        fit(
            mgmfrm_spec;
            experimental = true,
            init = mgmfrm_raw_params,
            seed = 20260630,
            ndraws = 2,
            warmup = 0,
            chains = 1,
            step_size = 0.02,
            max_depth = 2,
            metric = :unit,
        )
    @test mgmfrm_guarded_fit isa MGMFRMFit
    @test isempty(RuntimePublicLanguagePolicy.runtime_language_violations([
        "actual MGMFRMFit show" => sprint(show, mgmfrm_guarded_fit),
        "actual MGMFRMFit text/plain" =>
            sprint(show, MIME"text/plain"(), mgmfrm_guarded_fit),
    ]))
    @test_throws ArgumentError facets_report(mgmfrm_guarded_fit)
    @test_throws ArgumentError facets_compatibility_stats(mgmfrm_guarded_fit)
    @test mgmfrm_guarded_fit.design.spec.family === :mgmfrm
    @test mgmfrm_guarded_fit.backend === :advancedhmc
    @test mgmfrm_guarded_fit.sampler === :nuts
    @test size(mgmfrm_guarded_fit.draws) ==
        (2, mgmfrm_raw_blueprint.n_parameters)
    @test size(mgmfrm_guarded_fit.direct_draws) == (2, length(mgmfrm_params))
    @test size(mgmfrm_guarded_fit.direct_pointwise_loglikelihood) ==
        (2, identified_data.n)
    @test all(isfinite, mgmfrm_guarded_fit.log_posterior)
    @test all(isfinite, mgmfrm_guarded_fit.direct_draws)
    @test pointwise_loglikelihood_matrix(mgmfrm_guarded_fit) ==
        mgmfrm_guarded_fit.direct_pointwise_loglikelihood
    mgmfrm_direct_llmat = pointwise_loglikelihood_matrix(
        mgmfrm_guarded_fit.design,
        mgmfrm_guarded_fit.direct_draws)
    mgmfrm_raw_llmat = pointwise_loglikelihood_matrix(
        mgmfrm_guarded_fit.design,
        mgmfrm_guarded_fit.draws;
        parameter_space = :raw)
    @test mgmfrm_direct_llmat ≈
        mgmfrm_guarded_fit.direct_pointwise_loglikelihood
    @test mgmfrm_raw_llmat ≈
        mgmfrm_guarded_fit.direct_pointwise_loglikelihood
    @test_throws ArgumentError pointwise_loglikelihood_matrix(
        mgmfrm_guarded_fit.design,
        mgmfrm_guarded_fit.draws)
    @test waic(mgmfrm_guarded_fit.design,
        mgmfrm_guarded_fit.direct_draws).waic ≈
        waic(mgmfrm_guarded_fit).waic
    @test waic(mgmfrm_guarded_fit.design,
        mgmfrm_guarded_fit.draws;
        parameter_space = :raw).waic ≈
        waic(mgmfrm_guarded_fit).waic
    @test length(waic_diagnostics(mgmfrm_guarded_fit.design,
        mgmfrm_guarded_fit.draws;
        parameter_space = :raw)) == identified_data.n
    @test loglikelihood(mgmfrm_guarded_fit) ==
        mgmfrm_guarded_fit.direct_loglikelihood
    @test logprior(mgmfrm_guarded_fit) ≈
        mgmfrm_guarded_fit.log_posterior .-
        mgmfrm_guarded_fit.direct_loglikelihood
    @test logposterior(mgmfrm_guarded_fit) ==
        mgmfrm_guarded_fit.log_posterior
    @test logposterior(mgmfrm_guarded_fit; draw_indices = [2, 1]) ==
        mgmfrm_guarded_fit.log_posterior[[2, 1]]
    mgmfrm_probabilities =
        predictive_probabilities(mgmfrm_guarded_fit; draw_indices = [1, 2])
    @test size(mgmfrm_probabilities) ==
        (2, identified_data.n, length(identified_data.category_levels))
    @test all(draw -> all(row -> sum(mgmfrm_probabilities[draw, row, :]) ≈ 1.0,
        1:identified_data.n), 1:2)
    @test all(row -> log(mgmfrm_probabilities[1, row, identified_data.category[row]]) ≈
        mgmfrm_guarded_fit.direct_pointwise_loglikelihood[1, row],
        1:identified_data.n)
    mgmfrm_expected = expected_scores(mgmfrm_guarded_fit; draw_indices = [1, 2])
    mgmfrm_variances = predictive_variances(mgmfrm_guarded_fit; draw_indices = [1, 2])
    mgmfrm_residuals = predictive_residuals(mgmfrm_guarded_fit; draw_indices = [1, 2])
    @test size(mgmfrm_expected) == (2, identified_data.n)
    @test size(mgmfrm_variances) == (2, identified_data.n)
    @test size(mgmfrm_residuals) == (2, identified_data.n)
    @test all(>=(0.0), mgmfrm_variances)
    for draw in 1:2, row in 1:identified_data.n
        manual_mean = sum(identified_data.category_levels[k] *
            mgmfrm_probabilities[draw, row, k]
            for k in eachindex(identified_data.category_levels))
        @test mgmfrm_expected[draw, row] ≈ manual_mean
        @test mgmfrm_residuals[draw, row] ≈
            identified_data.score[row] - mgmfrm_expected[draw, row]
    end
    mgmfrm_replicated = posterior_predict(mgmfrm_guarded_fit;
        draw_indices = [1, 2],
        rng = MersenneTwister(20260632))
    @test size(mgmfrm_replicated) == (2, identified_data.n)
    @test all(score -> score in identified_data.category_levels, mgmfrm_replicated)
    mgmfrm_ppc = posterior_predictive_check(mgmfrm_guarded_fit;
        draw_indices = [1, 2],
        rng = MersenneTwister(20260633))
    @test size(mgmfrm_ppc.replicated_scores) == (2, identified_data.n)
    @test mgmfrm_ppc.category_levels == identified_data.category_levels
    @test !isempty(predictive_check_summary(mgmfrm_ppc; include_grouped = true))
    mgmfrm_calibration = calibration_table(mgmfrm_guarded_fit;
        draw_indices = [1, 2],
        bins = 2)
    @test length(mgmfrm_calibration) == 2
    @test all(row -> row.target === :expected_score, mgmfrm_calibration)
    @test all(row -> row.n_draws == 2, mgmfrm_calibration)
    mgmfrm_all_calibration = calibration_table(mgmfrm_guarded_fit;
        target = :all,
        draw_indices = [1, 2],
        bins = 2)
    @test any(row -> row.target === :category_probability,
        mgmfrm_all_calibration)
    mgmfrm_report = fit_report(mgmfrm_guarded_fit;
        draw_indices = [1, 2],
        include_loo = false,
        artifact_include_environment = false)
    mgmfrm_report_hash = artifact_content_hash(mgmfrm_report)
    mgmfrm_public_report = fit_report_public(mgmfrm_report)
    @test mgmfrm_public_report.schema ==
        "bayesianmgmfrm.fit_report_public.v1"
    @test mgmfrm_public_report.status === :experimental
    @test mgmfrm_public_report.source_report.content_hash ==
        BayesianMGMFRM._public_fit_report_content_hash_record(mgmfrm_report).value
    @test mgmfrm_report.category_functioning.status === :not_requested
    @test mgmfrm_report.rater_homogeneity.status === :not_requested
    @test artifact_content_hash(mgmfrm_report) == mgmfrm_report_hash
    @test !hasproperty(mgmfrm_public_report, :status_policy)
    @test !hasproperty(mgmfrm_public_report, :model_surface_audit)
    @test !occursin(r"experimental_public|guarded_local_fit|next_gate|test/fixtures/|scripts/generate_",
        JSON3.write(mgmfrm_public_report))
    @test isempty(RuntimePublicLanguagePolicy.runtime_language_violations([
        "actual MGMFRM public report" => JSON3.write(mgmfrm_public_report),
        "actual MGMFRM public Markdown" =>
            fit_report_markdown(mgmfrm_public_report; max_rows = 2),
    ]))
    @test mgmfrm_report.schema == "bayesianmgmfrm.fit_report.v1"
    @test mgmfrm_report.family === :mgmfrm
    @test mgmfrm_report.status_policy.status_label === :experimental_public
    @test mgmfrm_report.status_policy.experimental_public
    @test :broad_generalized_fit in mgmfrm_report.status_policy.blocked_claims
    @test :sparse_mgmfrm_superiority in mgmfrm_report.status_policy.blocked_claims
    @test mgmfrm_report.evidence_artifact_schema_policy.artifact_kind ===
        :fit_report
    @test :sparse_mgmfrm_superiority in
        mgmfrm_report.evidence_artifact_schema_policy.claim_policy.unsupported_claims
    @test mgmfrm_report.metadata.status_policy == mgmfrm_report.status_policy
    @test mgmfrm_report.metadata.dimension_labels == ["dim=1", "dim=2"]
    @test mgmfrm_report.model_surface_audit ==
        model_surface_audit(mgmfrm_guarded_fit)
    @test any(row -> row.block === :item_dimension_discrimination &&
        row.current_status === :experimental_public &&
        row.public_fit &&
        row.experimental_public &&
        row.fit_ready &&
        row.raw_coordinate === :log_item_dimension_discrimination &&
        row.report_label === :dimension_loading,
        mgmfrm_report.model_surface_audit)
    @test mgmfrm_report.metadata.guarded_local_fit
    @test mgmfrm_report.report_policy.resolved_draw_indices == [1, 2]
    @test mgmfrm_report.q_matrix.status === :computed
    @test mgmfrm_report.q_matrix.q_matrix == q_matrix
    @test mgmfrm_report.q_matrix.dimension_labels == ["dim=1", "dim=2"]
    @test mgmfrm_report.q_matrix.summary.passed
    @test any(row -> row.check === :cross_loading_policy &&
        row.status === :simple_structure,
        mgmfrm_report.q_matrix.rows)
    @test any(row -> row.gauge === :latent_correlation &&
        row.status === :fixed &&
        row.value === :identity,
        mgmfrm_report.q_matrix.gauge_rows)
    @test any(row -> row.gauge === :ability_scale &&
        row.value === :unit_variance_by_dimension,
        mgmfrm_report.q_matrix.gauge_rows)
    @test any(row -> row.option === :latent_correlation &&
        row.status === :blocked,
        mgmfrm_report.q_matrix.blocked_alternatives)
    @test mgmfrm_report.q_matrix.initialization_policy.initial_source ===
        :user_supplied_raw
    @test !mgmfrm_report.q_matrix.initialization_policy.fallback_used
    @test any(row -> row.policy === :initial_raw_vector &&
        row.status === :user_supplied_raw &&
        !row.fallback_used &&
        row.passed,
        mgmfrm_report.q_matrix.initialization_rows)
    @test any(row -> row.policy === :latent_correlation &&
        row.status === :fixed_identity &&
        row.value === :identity &&
        row.passed,
        mgmfrm_report.q_matrix.fixed_q_invariance_rows)
    @test any(row -> row.policy === :interpreted_loading_values &&
        row.status === :passed &&
        row.value == 0 &&
        row.passed,
        mgmfrm_report.q_matrix.fixed_q_invariance_rows)
    @test any(row -> row.policy === :direct_constraints &&
        row.status === :passed &&
        row.value == 0 &&
        row.passed,
        mgmfrm_report.q_matrix.fixed_q_invariance_rows)
    @test any(row -> row.policy === :rotation &&
        row.status === :not_applicable_fixed_q &&
        row.value === :blocked,
        mgmfrm_report.q_matrix.fixed_q_invariance_rows)
    @test any(row -> row.policy === :exploratory_loading &&
        row.status === :blocked,
        mgmfrm_report.q_matrix.fixed_q_invariance_rows)
    @test mgmfrm_report.prior_policy.status === :computed
    @test mgmfrm_report.prior_policy.summary.raw_coordinate_generalized_priors
    @test !mgmfrm_report.prior_policy.summary.direct_scale_generalized_priors_enabled
    @test mgmfrm_report.prior_policy.summary.jacobian_policy ===
        :none_raw_coordinate_density
    @test mgmfrm_report.prior_policy.summary.raw_prior_control_manifest_recorded
    @test mgmfrm_report.prior_policy.summary.raw_prior_control_all_active_scales_resolved
    @test mgmfrm_report.prior_policy.raw_prior_control_manifest.schema ==
        "bayesianmgmfrm.generalized_raw_prior_control_manifest.v1"
    @test any(row -> row.raw_block === :log_item_dimension_discrimination &&
        row.scale == mgmfrm_guarded_fit.prior.log_discrimination_sd,
        mgmfrm_report.prior_policy.raw_prior_control_manifest.rows)
    @test any(row -> row.block === :log_item_dimension_discrimination &&
        row.parameter_space === :raw_log_positive_coordinate &&
        row.scale_parameter === :log_discrimination_sd &&
        row.status === :active,
        mgmfrm_report.prior_policy.rows)
    @test any(row -> row.block === :direct_scale_generalized_priors &&
        row.status === :blocked &&
        row.jacobian_policy === :requires_future_log_jacobian_policy,
        mgmfrm_report.prior_policy.rows)
    @test mgmfrm_report.pooling_policy.status === :computed
    @test mgmfrm_report.pooling_policy.summary.independent_priors_default
    @test !mgmfrm_report.pooling_policy.summary.hierarchical_pooling_active
    @test any(row -> row.pooling === :hierarchical_rater_consistency_pooling &&
        row.status === :blocked,
        mgmfrm_report.pooling_policy.rows)
    @test mgmfrm_report.mcmc_budget_guidance.status === :computed
    @test mgmfrm_report.mcmc_budget_guidance.schema ==
        "bayesianmgmfrm.fit_report_mcmc_budget_guidance.v1"
    @test mgmfrm_report.mcmc_budget_guidance.n_rows == 5
    @test !mgmfrm_report.mcmc_budget_guidance.summary.current_budget_meets_guidance
    @test mgmfrm_report.mcmc_budget_guidance.summary.recommended_preset === :brms_like
    @test mgmfrm_report.mcmc_budget_guidance.summary.recommended_min_chains == 4
    @test mgmfrm_report.mcmc_budget_guidance.summary.recommended_min_warmup_per_chain == 1000
    @test mgmfrm_report.mcmc_budget_guidance.summary.recommended_min_draws_per_chain == 1000
    @test mgmfrm_report.mcmc_budget_guidance.summary.recommended_total_iterations_per_chain == 2000
    @test mgmfrm_report.mcmc_budget_guidance.summary.recommended_total_retained_draws == 4000
    @test !mgmfrm_report.mcmc_budget_guidance.summary.thinning_primary_fix
    @test !mgmfrm_report.mcmc_budget_guidance.summary.package_default_change
    @test any(row -> row.recommendation === :local_mgmfrm_diagnostic_budget &&
        row.status === :not_met &&
        row.action === :increase_budget_before_substantive_rank_warning_interpretation &&
        !row.package_default_change &&
        !row.public_claim_allowed,
        mgmfrm_report.mcmc_budget_guidance.rows)
    @test any(row -> row.recommendation === :thinning_policy &&
        row.status === :not_primary_fix &&
        row.action === :do_not_use_thinning_as_primary_fix,
        mgmfrm_report.mcmc_budget_guidance.rows)
    @test any(row -> row.recommendation === :warmup_policy &&
        row.status === :below_brms_like_budget &&
        row.recommended_minimum == 1000,
        mgmfrm_report.mcmc_budget_guidance.rows)
    @test mgmfrm_report.prior_predictive.status === :not_requested
    @test mgmfrm_report.posterior.status === :computed
    @test mgmfrm_report.direct_posterior.status === :computed
    @test mgmfrm_report.calibration.status === :computed
    @test mgmfrm_report.calibration.n_rows == identified_data.n
    @test mgmfrm_report.waic.status === :computed
    @test mgmfrm_report.loo.status === :not_requested
    @test mgmfrm_report.dff.status === :not_requested
    @test mgmfrm_report.artifact.status === :computed
    @test mgmfrm_report.artifact.schema ==
        "bayesianmgmfrm.mgmfrm_experimental_fit_artifact.v1"
    @test mgmfrm_report.artifact.artifact === nothing
    @test length(mgmfrm_report.artifact.content_hash.value) == 64
    mgmfrm_cache_key = fit_cache_key(mgmfrm_spec;
        experimental = true,
        backend = :advancedhmc,
        ndraws = 2,
        warmup = 0,
        chains = 1,
        step_size = 0.02,
        init = mgmfrm_raw_params,
        seed = 20260630,
        max_depth = 2,
        metric = :unit)
    @test length(mgmfrm_cache_key) == 64
    @test mgmfrm_cache_key == fit_cache_key(mgmfrm_guarded_fit.design;
        experimental = true,
        backend = :advancedhmc,
        ndraws = 2,
        warmup = 0,
        chains = 1,
        step_size = 0.02,
        init = mgmfrm_raw_params,
        seed = 20260630,
        max_depth = 2,
        metric = :unit)
    mgmfrm_cache_dir = mktempdir()
    mgmfrm_cache_path = joinpath(mgmfrm_cache_dir, "mgmfrm_guarded_fit.jls")
    mgmfrm_cache_record = save_fit_cache(mgmfrm_cache_path, mgmfrm_guarded_fit;
        cache_key = mgmfrm_cache_key)
    @test mgmfrm_cache_record.object === :fit_cache
    @test mgmfrm_cache_record.fit isa MGMFRMFit
    @test mgmfrm_cache_record.cache_key == mgmfrm_cache_key
    @test mgmfrm_cache_record.artifact.schema ==
        "bayesianmgmfrm.mgmfrm_experimental_fit_artifact.v1"
    loaded_mgmfrm_cache = load_fit_cache(mgmfrm_cache_path;
        expected_cache_key = mgmfrm_cache_key)
    @test loaded_mgmfrm_cache isa MGMFRMFit
    @test loaded_mgmfrm_cache.draws == mgmfrm_guarded_fit.draws
    mgmfrm_reproduction_manifest = fit_reproduction_manifest(mgmfrm_guarded_fit;
        cache_record = mgmfrm_cache_record,
        cache_path = mgmfrm_cache_path,
        include_environment = false)
    @test mgmfrm_reproduction_manifest.status === :ready
    @test mgmfrm_reproduction_manifest.family === :mgmfrm
    @test mgmfrm_reproduction_manifest.fast_cached_draws.status === :ready
    @test mgmfrm_reproduction_manifest.fast_cached_draws.n_draws == 2
    @test mgmfrm_reproduction_manifest.fast_cached_draws.content_hash ==
        mgmfrm_cache_record.artifact_content_hash
    @test_throws ArgumentError fit_reproduction_manifest(gmfrm_experimental_fit;
        cache_record = mgmfrm_cache_record,
        cache_path = mgmfrm_cache_path,
        include_environment = false)
    mgmfrm_simulated_direct = simulate_responses(mgmfrm_spec, mgmfrm_params;
        preview = true,
        rng = MersenneTwister(20260634),
        output = :scores)
    mgmfrm_simulated_raw = simulate_responses(mgmfrm_spec, mgmfrm_raw_params;
        preview = true,
        parameter_space = :raw,
        rng = MersenneTwister(20260634),
        output = :scores)
    @test mgmfrm_simulated_direct == mgmfrm_simulated_raw
    @test length(mgmfrm_simulated_direct) == identified_data.n
    @test all(score -> score in identified_data.category_levels, mgmfrm_simulated_direct)
    @test_throws ArgumentError simulate_responses(mgmfrm_spec, mgmfrm_params;
        output = :scores)
    mgmfrm_design_recovery_direct = parameter_recovery(
        mgmfrm_preview,
        reshape(mgmfrm_params, 1, :),
        mgmfrm_params)
    @test length(mgmfrm_design_recovery_direct) == length(mgmfrm_params)
    @test all(row -> row.model_family === :mgmfrm, mgmfrm_design_recovery_direct)
    @test all(row -> row.parameter_space === :direct, mgmfrm_design_recovery_direct)
    @test all(row -> row.guarded_local_fit, mgmfrm_design_recovery_direct)
    @test [row.parameter for row in mgmfrm_design_recovery_direct] ==
        mgmfrm_preview.parameter_names
    mgmfrm_design_recovery_raw = parameter_recovery(
        mgmfrm_preview,
        reshape(mgmfrm_raw_params, 1, :),
        mgmfrm_raw_params;
        parameter_space = :raw)
    @test [row.parameter for row in mgmfrm_design_recovery_raw] ==
        mgmfrm_fit_ready_blueprint.parameter_names
    @test all(row -> row.density_space === :raw_unconstrained,
        mgmfrm_design_recovery_raw)
    mgmfrm_direct_truth = [
        sum(mgmfrm_guarded_fit.direct_draws[:, col]) /
            size(mgmfrm_guarded_fit.direct_draws, 1)
        for col in axes(mgmfrm_guarded_fit.direct_draws, 2)
    ]
    mgmfrm_fit_recovery_direct =
        parameter_recovery(mgmfrm_guarded_fit, mgmfrm_direct_truth)
    @test length(mgmfrm_fit_recovery_direct) == length(mgmfrm_params)
    @test all(row -> row.model_family === :mgmfrm, mgmfrm_fit_recovery_direct)
    @test all(row -> row.parameter_space === :direct, mgmfrm_fit_recovery_direct)
    @test all(row -> row.fit_ready && row.public_fit &&
        row.experimental_public && row.guarded_local_fit,
        mgmfrm_fit_recovery_direct)
    @test maximum(abs(row.bias) for row in mgmfrm_fit_recovery_direct) < 1e-12
    mgmfrm_raw_truth = [
        sum(mgmfrm_guarded_fit.draws[:, col]) /
            size(mgmfrm_guarded_fit.draws, 1)
        for col in axes(mgmfrm_guarded_fit.draws, 2)
    ]
    mgmfrm_fit_recovery_raw = parameter_recovery(mgmfrm_guarded_fit,
        mgmfrm_raw_truth;
        parameter_space = :raw)
    @test length(mgmfrm_fit_recovery_raw) == mgmfrm_raw_blueprint.n_parameters
    @test [row.parameter for row in mgmfrm_fit_recovery_raw] ==
        mgmfrm_fit_ready_blueprint.parameter_names
    @test parameter_recovery_summary(mgmfrm_guarded_fit, mgmfrm_direct_truth;
        by = :all)[1].n_parameters == length(mgmfrm_params)
    @test length(parameter_recovery_plot_data(mgmfrm_guarded_fit,
        mgmfrm_direct_truth)) == length(mgmfrm_params)
    mgmfrm_guarded_surface = mgmfrm_guarded_fit.diagnostic_surface
    @test mgmfrm_guarded_surface.schema ==
        "bayesianmgmfrm.mgmfrm_guarded_local_fit_sampler_diagnostics.v1"
    @test mgmfrm_guarded_surface.status === :guarded_local_fit
    @test mgmfrm_guarded_surface.public_fit
    @test mgmfrm_guarded_surface.experimental_public
    @test mgmfrm_guarded_surface.fit_ready
    @test mgmfrm_guarded_surface.target === :_mgmfrm_guarded_local_fit_logdensity
    @test mgmfrm_guarded_surface.summary.total_draws == 2
    @test mgmfrm_guarded_surface.summary.n_direct_parameters == length(mgmfrm_params)
    @test mgmfrm_guarded_surface.summary.n_failed_direct_constraints == 0
    @test all(row -> row.passed, mgmfrm_guarded_surface.direct_constraint_rows)
    @test mgmfrm_guarded_surface.initialization_policy.initial_source ===
        :user_supplied_raw
    @test !mgmfrm_guarded_surface.initialization_policy.fallback_used
    @test mgmfrm_guarded_surface.initialization_policy.finite_initial_logdensity
    @test any(row -> row.policy === :initial_logdensity &&
        row.status === :finite &&
        row.passed,
        mgmfrm_guarded_surface.initialization_rows)
    @test any(row -> row.policy === :loading_sign &&
        row.status === :fixed_positive &&
        row.value == count(identity, q_matrix),
        mgmfrm_guarded_surface.fixed_q_invariance_rows)
    @test any(row -> row.policy === :direct_constraints &&
        row.status === :passed &&
        row.value == 0,
        mgmfrm_guarded_surface.fixed_q_invariance_rows)
    @test [row.parameter for row in mgmfrm_guarded_surface.direct_parameter_rows] ==
        mgmfrm_preview.parameter_names
    mgmfrm_guarded_metadata = fit_metadata(mgmfrm_guarded_fit)
    @test mgmfrm_guarded_metadata.public_fit
    @test mgmfrm_guarded_metadata.experimental_public
    @test mgmfrm_guarded_metadata.fit_ready
    @test mgmfrm_guarded_metadata.guarded_local_fit
    @test mgmfrm_guarded_metadata.status_policy.status_label ===
        :experimental_public
    @test :sparse_mgmfrm_superiority in
        mgmfrm_guarded_metadata.status_policy.blocked_claims
    @test mgmfrm_guarded_metadata.scope === :minimal_confirmatory_mgmfrm_candidate
    @test isequal(
        mgmfrm_guarded_metadata,
        fit_metadata(mgmfrm_guarded_fit; view = :full),
    )
    mgmfrm_public_metadata = fit_metadata(
        mgmfrm_guarded_fit;
        view = :public,
    )
    @test mgmfrm_public_metadata.schema ==
        "bayesianmgmfrm.fit_metadata_public.v1"
    @test mgmfrm_public_metadata.family === :mgmfrm
    @test mgmfrm_public_metadata.stability === :experimental
    @test mgmfrm_public_metadata.estimation_status === :experimental
    @test mgmfrm_public_metadata.raw_parameter_names ==
        mgmfrm_guarded_metadata.raw_parameter_names
    @test isempty(intersect(
        Set(structured_field_names(mgmfrm_public_metadata)),
        PRIVATE_READER_FIT_FIELDS,
    ))
    @test reader_payload_is_identity_free(mgmfrm_public_metadata)
    @test_throws ArgumentError fit_metadata(
        mgmfrm_guarded_fit;
        view = :unknown,
    )
    mgmfrm_fit_audit = model_surface_audit(mgmfrm_guarded_fit)
    @test all(row -> row.current_status === :experimental_public,
        mgmfrm_fit_audit)
    @test any(row -> row.block === :rater_consistency &&
        row.prior_scale === :log_consistency_sd &&
        row.report_label === :rater_consistency,
        mgmfrm_fit_audit)
    mgmfrm_guarded_diagnostics = diagnostics(mgmfrm_guarded_fit)
    @test mgmfrm_guarded_diagnostics.schema ==
        "bayesianmgmfrm.mgmfrm_guarded_local_fit_diagnostics.v1"
    @test mgmfrm_guarded_diagnostics.public_fit
    @test mgmfrm_guarded_diagnostics.experimental_public
    @test mgmfrm_guarded_diagnostics.fit_ready
    @test mgmfrm_guarded_diagnostics.guarded_local_fit
    @test mgmfrm_guarded_diagnostics.parameter_layout.schema ==
        "bayesianmgmfrm.fit_ready_parameter_layout.v1"
    @test mgmfrm_guarded_diagnostics.parameter_layout.raw_parameter_names ==
        mgmfrm_guarded_fit.diagnostic_surface.raw_parameter_names
    @test mgmfrm_guarded_diagnostics.parameter_layout.constrained_parameter_names ==
        mgmfrm_guarded_fit.diagnostic_surface.direct_parameter_names
    @test mgmfrm_guarded_diagnostics.diagnostic_row_policy.family === :mgmfrm
    @test mgmfrm_guarded_diagnostics.diagnostic_row_policy.parameter_spaces ==
        (:raw_unconstrained, :direct_constrained)
    @test mgmfrm_guarded_diagnostics.diagnostic_row_policy.rhat_ess_status ===
        :rank_normalized_available
    @test mgmfrm_guarded_diagnostics.initialization_policy.initial_source ===
        :user_supplied_raw
    @test any(row -> row.policy === :initial_direct_transform &&
        row.parameter_space === :direct_constrained &&
        row.passed,
        mgmfrm_guarded_diagnostics.initialization_rows)
    @test any(row -> row.policy === :dimension_permutation &&
        row.status === :anchored_by_fixed_q_dimension_labels,
        mgmfrm_guarded_diagnostics.fixed_q_invariance_rows)
    @test isequal(
        mgmfrm_guarded_diagnostics,
        diagnostics(mgmfrm_guarded_fit; view = :full),
    )
    mgmfrm_public_diagnostics = diagnostics(
        mgmfrm_guarded_fit;
        view = :public,
    )
    @test mgmfrm_public_diagnostics.schema ==
        "bayesianmgmfrm.diagnostics_public.v1"
    @test mgmfrm_public_diagnostics.family === :mgmfrm
    @test mgmfrm_public_diagnostics.stability === :experimental
    @test public_portable_numeric_summary_matches(
        mgmfrm_public_diagnostics.summary.raw_diagnostic_metrics,
        mgmfrm_guarded_diagnostics.summary.raw_diagnostic_metrics,
    )
    @test mgmfrm_public_diagnostics.parameter_layout.raw_parameter_names ==
        mgmfrm_guarded_diagnostics.parameter_layout.raw_parameter_names
    @test all(row -> !(row.value isa AbstractString &&
            occursin(r"^[0-9a-fA-F]{64}$", row.value)),
        mgmfrm_public_diagnostics.initialization_rows)
    @test only(filter(row -> row.policy === :latent_correlation,
        mgmfrm_public_diagnostics.fixed_q_invariance_rows)).note ===
        :free_latent_correlation_not_supported
    @test only(filter(row -> row.policy === :rotation,
        mgmfrm_public_diagnostics.fixed_q_invariance_rows)).value ===
        :not_supported
    @test only(filter(row -> row.policy === :exploratory_loading,
        mgmfrm_public_diagnostics.fixed_q_invariance_rows)).status ===
        :not_supported
    @test isempty(intersect(
        Set(structured_field_names(mgmfrm_public_diagnostics)),
        PRIVATE_READER_FIT_FIELDS,
    ))
    @test reader_payload_is_identity_free(mgmfrm_public_diagnostics)
    @test_throws ArgumentError diagnostics(
        mgmfrm_guarded_fit;
        view = :unknown,
    )
    @test length(sampler_diagnostics(mgmfrm_guarded_fit)) == 1
    @test all(row -> row.diagnostic_row === :sampler_chain &&
        row.parameter_space === :raw_unconstrained &&
        row.diagnostic_method === :sampler_chain_summary,
        sampler_diagnostics(mgmfrm_guarded_fit))
    @test length(mcmc_diagnostics(mgmfrm_guarded_fit)) ==
        size(mgmfrm_guarded_fit.draws, 2)
    @test all(row -> row.diagnostic_row === :parameter &&
        row.parameter_space === :raw_unconstrained &&
        row.diagnostic_method === :rank_normalized_split_rhat_bulk_tail_ess &&
        row.diagnostic_status === :rank_normalized_available &&
        row.flag === row.rank_normalized_flag,
        mcmc_diagnostics(mgmfrm_guarded_fit))
    @test length(parameter_block_diagnostics(mgmfrm_guarded_fit)) >= 1
    @test all(row -> row.diagnostic_row === :parameter_block &&
        row.parameter_space === :raw_unconstrained &&
        row.diagnostic_method === :rank_normalized_split_rhat_bulk_tail_ess &&
        row.diagnostic_status === :rank_normalized_available,
        parameter_block_diagnostics(mgmfrm_guarded_fit))
    @test all(row -> row.parameter_space === :direct_constrained &&
        row.diagnostic_method === :rank_normalized_split_rhat_bulk_tail_ess &&
        ((row.quality_gate_applicable &&
                row.diagnostic_status === :rank_normalized_available &&
                row.flag === row.rank_normalized_flag) ||
            (!row.quality_gate_applicable &&
                row.diagnostic_status === :structurally_fixed &&
                row.flag === :structurally_fixed &&
                row.classical_compatibility_flag === :structurally_fixed)),
        mgmfrm_guarded_diagnostics.direct_parameter_rows)
    @test all(row -> row.diagnostic_row === :parameter_block &&
        row.parameter_space === :direct_constrained &&
        row.diagnostic_method === :rank_normalized_split_rhat_bulk_tail_ess &&
        row.diagnostic_status in
            (:rank_normalized_available, :structurally_fixed),
        mgmfrm_guarded_diagnostics.direct_block_rows)
    mgmfrm_guarded_artifact =
        fit_artifact(mgmfrm_guarded_fit; include_environment = false)
    @test mgmfrm_guarded_artifact.schema ==
        "bayesianmgmfrm.mgmfrm_experimental_fit_artifact.v1"
    @test mgmfrm_guarded_artifact.public_fit
    @test mgmfrm_guarded_artifact.experimental_public
    @test mgmfrm_guarded_artifact.guarded_local_fit
    @test mgmfrm_guarded_artifact.fit_ready
    @test mgmfrm_guarded_artifact.reproducibility.diagnostic_policy.diagnostic_contract ===
        :rank_normalized_rhat_bulk_tail_ess_v1
    @test mgmfrm_guarded_artifact.reproducibility.diagnostic_policy.diagnostic_contract_details.id ===
        :rank_normalized_rhat_bulk_tail_ess_v1
    @test mgmfrm_guarded_artifact.public_target_label ===
        :guarded_confirmatory_mgmfrm_logdensity
    @test mgmfrm_guarded_artifact.public_target_description ==
        "guarded fixed-Q confirmatory MGMFRM log density"
    @test mgmfrm_guarded_artifact.internal_target_constructor ===
        :_mgmfrm_guarded_local_fit_logdensity
    @test mgmfrm_guarded_artifact.internal_sampler_diagnostic_constructor ===
        :_mgmfrm_guarded_local_fit_sampler_diagnostics
    @test mgmfrm_guarded_artifact.evidence_artifact_schema_policy.artifact_kind ===
        :mgmfrm_experimental_fit_artifact
    @test :sparse_mgmfrm_superiority in
        mgmfrm_guarded_artifact.evidence_artifact_schema_policy.claim_policy.unsupported_claims
    @test mgmfrm_guarded_artifact.evidence_artifact_schema_policy.environment_policy.include_environment ===
        false
    @test mgmfrm_guarded_artifact.entrypoint ==
        "BayesianMGMFRM.Experimental.fit(spec)"
    @test mgmfrm_guarded_artifact.legacy_entrypoint ==
        "BayesianMGMFRM.fit(spec; experimental = true)"
    @test mgmfrm_guarded_artifact.guarded_local_entrypoint === :_fit_guarded_mgmfrm
    @test mgmfrm_guarded_artifact.target === :_mgmfrm_guarded_local_fit_logdensity
    mgmfrm_public_artifact = fit_artifact(
        mgmfrm_guarded_fit;
        view = :public,
        include_environment = false,
    )
    @test mgmfrm_public_artifact.schema ==
        "bayesianmgmfrm.fit_artifact_public.v1"
    @test mgmfrm_public_artifact.stability === :experimental
    @test mgmfrm_public_artifact.content_hash.value ==
        artifact_content_hash(mgmfrm_public_artifact)
    @test :internal_target_constructor ∉ keys(mgmfrm_public_artifact)
    @test :internal_sampler_diagnostic_constructor ∉
        keys(mgmfrm_public_artifact)
    @test :guarded_local_entrypoint ∉ keys(mgmfrm_public_artifact)
    @test :target ∉ keys(mgmfrm_public_artifact)
    @test :fixture_provenance ∉ keys(mgmfrm_public_artifact)
    mgmfrm_public_surface = model_surface_audit(
        mgmfrm_guarded_fit;
        view = :public,
    )
    @test all(row -> row.execution_status === :experimental &&
        row.fit_available &&
        row.fit_entrypoint == "BayesianMGMFRM.Experimental.fit(spec)" &&
        row.claim_scope === :fixed_q_confirmatory_only &&
        :block_status ∉ keys(row),
        mgmfrm_public_surface)
    @test any(row -> row.declaration_status === :specified_only,
        mgmfrm_public_surface)
    @test mgmfrm_guarded_artifact.ability_scale ===
        :standard_normal_by_dimension
    @test mgmfrm_guarded_artifact.initialization_policy ==
        mgmfrm_guarded_fit.diagnostic_surface.initialization_policy
    @test any(row -> row.policy === :initial_raw_vector &&
        row.status === :user_supplied_raw &&
        row.passed,
        mgmfrm_guarded_artifact.initialization_rows)
    @test any(row -> row.policy === :interpreted_loading_values &&
        row.status === :passed &&
        row.passed,
        mgmfrm_guarded_artifact.fixed_q_invariance_rows)
    @test any(row -> row.policy === :exploratory_loading &&
        row.status === :blocked,
        mgmfrm_guarded_artifact.fixed_q_invariance_rows)
    @test mgmfrm_guarded_artifact.raw_prior_control_manifest.schema ==
        "bayesianmgmfrm.generalized_raw_prior_control_manifest.v1"
    @test mgmfrm_guarded_artifact.raw_prior_control_manifest.resolved
    @test mgmfrm_guarded_artifact.raw_prior_control_manifest.summary.all_active_scales_resolved
    @test any(row -> row.raw_block === :log_item_dimension_discrimination &&
        row.scale_parameter === :log_discrimination_sd &&
        row.scale == mgmfrm_guarded_fit.prior.log_discrimination_sd &&
        row.scale_status === :resolved_from_source_fixture_prior,
        mgmfrm_guarded_artifact.raw_prior_control_manifest.rows)
    @test any(row -> row.raw_block === :log_rater_consistency_free &&
        row.scale_parameter === :log_consistency_sd &&
        row.scale == mgmfrm_guarded_fit.prior.log_consistency_sd,
        mgmfrm_guarded_artifact.raw_prior_control_manifest.rows)
    @test isequal(mgmfrm_guarded_artifact.parameter_layout,
        mgmfrm_guarded_diagnostics.parameter_layout)
    @test size(mgmfrm_guarded_artifact.pointwise_loglikelihood) ==
        (2, identified_data.n)
    @test mgmfrm_guarded_artifact.raw_to_direct_transform ==
        mgmfrm_guarded_artifact.parameter_layout.transforms
    @test !isempty(mgmfrm_guarded_artifact.raw_to_direct_transform)
    @test mgmfrm_guarded_artifact.raw_posterior_row_schema.schema ==
        "bayesianmgmfrm.posterior_summary_row_schema.v1"
    @test mgmfrm_guarded_artifact.raw_posterior_row_schema.parameter_space ===
        :raw_unconstrained
    @test mgmfrm_guarded_artifact.raw_posterior_row_schema.parameter_names ==
        mgmfrm_guarded_artifact.raw_parameter_names
    @test mgmfrm_guarded_artifact.raw_posterior_row_schema.row_fields ==
        propertynames(first(mgmfrm_guarded_artifact.posterior_summary))
    @test mgmfrm_guarded_artifact.direct_posterior_row_schema.schema ==
        "bayesianmgmfrm.posterior_summary_row_schema.v1"
    @test mgmfrm_guarded_artifact.direct_posterior_row_schema.parameter_space ===
        :constrained_direct
    @test mgmfrm_guarded_artifact.direct_posterior_row_schema.parameter_names ==
        mgmfrm_guarded_artifact.direct_parameter_names
    @test mgmfrm_guarded_artifact.direct_posterior_row_schema.row_fields ==
        propertynames(first(mgmfrm_guarded_artifact.direct_posterior_summary))
    @test !isempty(mgmfrm_guarded_artifact.fixture_provenance)
    @test isnothing(mgmfrm_guarded_artifact.raw_draws)
    @test isnothing(mgmfrm_guarded_artifact.direct_draws)
    @test mgmfrm_guarded_artifact.content_hash.value ==
        artifact_content_hash(mgmfrm_guarded_artifact)
    @test mgmfrm_guarded_artifact.archive_manifest.content_hash ==
        mgmfrm_guarded_artifact.content_hash
    @test waic(mgmfrm_guarded_fit).n_draws == 2
    @test length(waic_diagnostics(mgmfrm_guarded_fit)) == identified_data.n
    @test_throws ArgumentError compare_models(
        gmfrm_experimental_fit,
        mgmfrm_guarded_fit;
        draw_indices = [1, 2])

    mgmfrm3_table = (
        examinee = ["E1", "E1", "E1", "E2", "E2", "E2"],
        rater = ["R1", "R2", "R1", "R2", "R1", "R2"],
        item = ["I1", "I2", "I3", "I1", "I2", "I3"],
        score = [0, 1, 2, 1, 0, 2],
    )
    mgmfrm3_data = FacetData(mgmfrm3_table;
        person = :examinee,
        rater = :rater,
        item = :item,
        score = :score)
    q_matrix3 = Bool[
        1 0 0
        0 1 0
        0 0 1
    ]
    mgmfrm3_spec = mfrm_spec(mgmfrm3_data;
        thresholds = :partial_credit,
        family = :mgmfrm,
        dimensions = 3,
        q_matrix = q_matrix3)
    @test mgmfrm3_spec.dimensions == 3
    @test mgmfrm3_spec.q_matrix == q_matrix3
    @test q_matrix_validation(mgmfrm3_spec).passed
    mgmfrm3_preview = getdesign(mgmfrm3_spec; preview = true)
    @test mgmfrm3_preview.parameter_names[mgmfrm3_preview.blocks[:person]] == [
        "person[E1,dim=1]",
        "person[E1,dim=2]",
        "person[E1,dim=3]",
        "person[E2,dim=1]",
        "person[E2,dim=2]",
        "person[E2,dim=3]",
    ]
    @test length(mgmfrm3_preview.parameter_names[
        mgmfrm3_preview.blocks[:item_dimension_discrimination]]) == count(q_matrix3)
    mgmfrm3_layout = fit_ready_parameter_layout(mgmfrm3_spec; preview = true)
    @test mgmfrm3_layout.scope === :minimal_confirmatory_mgmfrm_candidate
    @test mgmfrm3_layout.experimental_public
    mgmfrm3_target =
        BayesianMGMFRM._mgmfrm_guarded_local_fit_logdensity(
            mgmfrm3_preview;
            prior = source_prior,
        )
    mgmfrm3_raw_initial = initial_params(mgmfrm3_target)
    @test LogDensityProblems.dimension(mgmfrm3_target) ==
        length(mgmfrm3_layout.raw_parameter_names)
    @test isfinite(LogDensityProblems.logdensity(
        mgmfrm3_target,
        mgmfrm3_raw_initial,
    ))
    mgmfrm3_direct_initial =
        BayesianMGMFRM._mgmfrm_source_constrained_params_from_unconstrained(
            mgmfrm3_preview,
            mgmfrm3_raw_initial,
        )
    mgmfrm3_pointwise_fixture =
        BayesianMGMFRM._mgmfrm_confirmatory_candidate_pointwise_fixture(
            mgmfrm3_preview,
            mgmfrm3_direct_initial,
    )
    @test mgmfrm3_pointwise_fixture.summary.passed
    @test mgmfrm3_pointwise_fixture.q_matrix == q_matrix3
    @test length(mgmfrm3_pointwise_fixture.pointwise_loglikelihood) ==
        mgmfrm3_data.n
    mgmfrm3_fit = fit(
        mgmfrm3_spec;
        experimental = true,
        init = mgmfrm3_raw_initial,
        seed = 20260704,
        ndraws = 1,
        warmup = 0,
        chains = 1,
        step_size = 0.02,
        max_depth = 2,
        metric = :unit,
    )
    @test mgmfrm3_fit isa MGMFRMFit
    @test mgmfrm3_fit.design.spec.dimensions == 3
    @test size(mgmfrm3_fit.draws) ==
        (1, LogDensityProblems.dimension(mgmfrm3_target))
    @test size(mgmfrm3_fit.direct_pointwise_loglikelihood) ==
        (1, mgmfrm3_data.n)
    @test all(isfinite, mgmfrm3_fit.log_posterior)
    @test all(isfinite, mgmfrm3_fit.direct_pointwise_loglikelihood)
    @test mgmfrm3_fit.diagnostic_surface.summary.n_failed_direct_constraints == 0
    mgmfrm3_standardized_residuals = predictive_standardized_residuals(
        mgmfrm3_fit;
        draw_indices = [1],
    )
    @test mgmfrm3_standardized_residuals.family === :mgmfrm
    @test mgmfrm3_standardized_residuals.draw_indices == (1,)
    @test size(mgmfrm3_standardized_residuals.values) == (1, mgmfrm3_data.n)

    @test_throws ArgumentError BayesianMGMFRM._fit_guarded_mgmfrm(
        gmfrm_spec;
        ndraws = 1,
        warmup = 0,
    )
    mgmfrm_bridge_fixture = optional_source_bridge_fixture_path(
        "MFRM_SOURCE_MGMFRM_BRIDGESTAN_FIXTURE",
        joinpath("test", "fixtures", "source_mgmfrm_bridge_logdensity.json"),
        joinpath("test", "stan", "source_mgmfrm_fixture.stan"))
    if !isempty(mgmfrm_bridge_fixture)
        check_source_bridge_fixture(
            mgmfrm_bridge_fixture,
            mgmfrm_target;
            expected_schema = "bayesianmgmfrm.source_mgmfrm_bridge_logdensity.v1",
            expected_stan_model = "test/stan/source_mgmfrm_fixture.stan",
        )
        check_mgmfrm_bridge_confirmatory_fixture(mgmfrm_bridge_fixture, mgmfrm_target)
    end
    mgmfrm_candidate_chain_study_fixture = optional_fixture_path("MFRM_MGMFRM_CANDIDATE_CHAIN_STUDY_FIXTURE", joinpath("test", "fixtures", "mgmfrm_candidate_chain_study.json"))
    if !isempty(mgmfrm_candidate_chain_study_fixture)
        check_mgmfrm_candidate_chain_study_fixture(
            mgmfrm_candidate_chain_study_fixture,
            mgmfrm_target,
            mgmfrm_raw_params,
        )
    end
    mgmfrm_recovery_smoke_fixture = optional_fixture_path("MFRM_MGMFRM_RECOVERY_SMOKE_FIXTURE", joinpath("test", "fixtures", "mgmfrm_recovery_smoke.json"))
    if !isempty(mgmfrm_recovery_smoke_fixture)
        check_mgmfrm_recovery_smoke_fixture(mgmfrm_recovery_smoke_fixture)
    end
    mgmfrm_baseline_comparison_fixture = optional_fixture_path("MFRM_MGMFRM_BASELINE_COMPARISON_FIXTURE", joinpath("test", "fixtures", "mgmfrm_baseline_comparison.json"))
    if !isempty(mgmfrm_baseline_comparison_fixture)
        check_mgmfrm_baseline_comparison_fixture(
            mgmfrm_baseline_comparison_fixture,
        )
    end
    mgmfrm_sparse_recovery_grid_fixture = optional_fixture_path("MFRM_MGMFRM_SPARSE_RECOVERY_GRID_FIXTURE", joinpath("test", "fixtures", "mgmfrm_sparse_recovery_grid.json"))
    if !isempty(mgmfrm_sparse_recovery_grid_fixture)
        check_mgmfrm_sparse_recovery_grid_fixture(
            mgmfrm_sparse_recovery_grid_fixture,
        )
    end
    mgmfrm_report_shape_simulation_grid_fixture = optional_fixture_path("MFRM_MGMFRM_REPORT_SHAPE_SIMULATION_GRID_FIXTURE", joinpath("test", "fixtures", "mgmfrm_report_shape_simulation_grid.json"))
    if !isempty(mgmfrm_report_shape_simulation_grid_fixture)
        check_mgmfrm_report_shape_simulation_grid_fixture(
            mgmfrm_report_shape_simulation_grid_fixture,
        )
    end
    mgmfrm_q_matrix_validation_expansion_fixture = optional_fixture_path("MFRM_MGMFRM_Q_MATRIX_VALIDATION_EXPANSION_FIXTURE", joinpath("test", "fixtures", "mgmfrm_q_matrix_validation_expansion.json"))
    if !isempty(mgmfrm_q_matrix_validation_expansion_fixture)
        check_mgmfrm_q_matrix_validation_expansion_fixture(
            mgmfrm_q_matrix_validation_expansion_fixture,
        )
    end
    mgmfrm_empirical_q_matrix_recovery_policy_fixture = optional_fixture_path("MFRM_MGMFRM_EMPIRICAL_Q_MATRIX_RECOVERY_POLICY_FIXTURE", joinpath("test", "fixtures", "mgmfrm_empirical_q_matrix_recovery_policy.json"))
    if !isempty(mgmfrm_empirical_q_matrix_recovery_policy_fixture)
        check_mgmfrm_empirical_q_matrix_recovery_policy_fixture(
            mgmfrm_empirical_q_matrix_recovery_policy_fixture,
        )
    end
    mgmfrm_empirical_q_matrix_recovery_simulation_grid_fixture = optional_fixture_path("MFRM_MGMFRM_EMPIRICAL_Q_MATRIX_RECOVERY_SIMULATION_GRID_FIXTURE", joinpath("test", "fixtures", "mgmfrm_empirical_q_matrix_recovery_simulation_grid.json"))
    if !isempty(mgmfrm_empirical_q_matrix_recovery_simulation_grid_fixture)
        check_mgmfrm_empirical_q_matrix_recovery_simulation_grid_fixture(
            mgmfrm_empirical_q_matrix_recovery_simulation_grid_fixture,
        )
    end
    mgmfrm_literature_anchored_synthetic_benchmark_fixture = optional_fixture_path("MFRM_MGMFRM_LITERATURE_ANCHORED_SYNTHETIC_BENCHMARK_FIXTURE", joinpath("test", "fixtures", "mgmfrm_literature_anchored_synthetic_benchmark.json"))
    if !isempty(mgmfrm_literature_anchored_synthetic_benchmark_fixture)
        check_mgmfrm_literature_anchored_synthetic_benchmark_fixture(
            mgmfrm_literature_anchored_synthetic_benchmark_fixture,
        )
    end
    mgmfrm_tam_overlap_baseline_fixture = optional_fixture_path("MFRM_MGMFRM_TAM_OVERLAP_BASELINE_FIXTURE", joinpath("test", "fixtures", "mgmfrm_tam_overlap_baseline.json"))
    if !isempty(mgmfrm_tam_overlap_baseline_fixture)
        check_mgmfrm_tam_overlap_baseline_fixture(
            mgmfrm_tam_overlap_baseline_fixture,
        )
    end
    mgmfrm_tam_overlap_execution_review_fixture = optional_fixture_path("MFRM_MGMFRM_TAM_OVERLAP_EXECUTION_REVIEW_FIXTURE", joinpath("test", "fixtures", "mgmfrm_tam_overlap_execution_review.json"))
    if !isempty(mgmfrm_tam_overlap_execution_review_fixture)
        check_mgmfrm_tam_overlap_execution_review_fixture(
            mgmfrm_tam_overlap_execution_review_fixture,
        )
    end
    mgmfrm_tam_comparison_policy_review_fixture = optional_fixture_path("MFRM_MGMFRM_TAM_COMPARISON_POLICY_REVIEW_FIXTURE", joinpath("test", "fixtures", "mgmfrm_tam_comparison_policy_review.json"))
    if !isempty(mgmfrm_tam_comparison_policy_review_fixture)
        check_mgmfrm_tam_comparison_policy_review_fixture(
            mgmfrm_tam_comparison_policy_review_fixture,
        )
    end
    mgmfrm_tam_multireplication_comparison_fixture = optional_fixture_path("MFRM_MGMFRM_TAM_MULTIREPLICATION_COMPARISON_FIXTURE", joinpath("test", "fixtures", "mgmfrm_tam_multireplication_comparison.json"))
    if !isempty(mgmfrm_tam_multireplication_comparison_fixture)
        check_mgmfrm_tam_multireplication_comparison_fixture(
            mgmfrm_tam_multireplication_comparison_fixture,
        )
    end
    mgmfrm_tam_direct_estimate_pilot_fixture = optional_fixture_path("MFRM_MGMFRM_TAM_DIRECT_ESTIMATE_PILOT_FIXTURE", joinpath("test", "fixtures", "mgmfrm_tam_direct_estimate_pilot.json"))
    if !isempty(mgmfrm_tam_direct_estimate_pilot_fixture)
        check_mgmfrm_tam_direct_estimate_pilot_fixture(
            mgmfrm_tam_direct_estimate_pilot_fixture,
        )
    end
    mgmfrm_tam_direct_agreement_policy_fixture = optional_fixture_path("MFRM_MGMFRM_TAM_DIRECT_AGREEMENT_POLICY_FIXTURE", joinpath("test", "fixtures", "mgmfrm_tam_direct_agreement_policy.json"))
    if !isempty(mgmfrm_tam_direct_agreement_policy_fixture)
        check_mgmfrm_tam_direct_agreement_policy_fixture(
            mgmfrm_tam_direct_agreement_policy_fixture,
        )
    end
    mgmfrm_tam_direct_agreement_policy_refinement_fixture = optional_fixture_path("MFRM_MGMFRM_TAM_DIRECT_AGREEMENT_POLICY_REFINEMENT_FIXTURE", joinpath("test", "fixtures", "mgmfrm_tam_direct_agreement_policy_refinement.json"))
    if !isempty(mgmfrm_tam_direct_agreement_policy_refinement_fixture)
        check_mgmfrm_tam_direct_agreement_policy_refinement_fixture(
            mgmfrm_tam_direct_agreement_policy_refinement_fixture,
        )
    end
    mgmfrm_tam_direct_agreement_multireplication_fixture = optional_fixture_path("MFRM_MGMFRM_TAM_DIRECT_AGREEMENT_MULTIREPLICATION_FIXTURE", joinpath("test", "fixtures", "mgmfrm_tam_direct_agreement_multireplication.json"))
    if !isempty(mgmfrm_tam_direct_agreement_multireplication_fixture)
        check_mgmfrm_tam_direct_agreement_multireplication_fixture(
            mgmfrm_tam_direct_agreement_multireplication_fixture,
        )
    end
    mgmfrm_tam_direct_agreement_raw_archive_audit_fixture = optional_fixture_path("MFRM_MGMFRM_TAM_DIRECT_AGREEMENT_RAW_ARCHIVE_AUDIT_FIXTURE", joinpath("test", "fixtures", "mgmfrm_tam_direct_agreement_raw_archive_audit.json"))
    if !isempty(mgmfrm_tam_direct_agreement_raw_archive_audit_fixture)
        check_mgmfrm_tam_direct_agreement_raw_archive_audit_fixture(
            mgmfrm_tam_direct_agreement_raw_archive_audit_fixture,
        )
    end
    mgmfrm_tam_direct_agreement_post_execution_review_packet_fixture = optional_fixture_path("MFRM_MGMFRM_TAM_DIRECT_AGREEMENT_POST_EXECUTION_REVIEW_PACKET_FIXTURE", joinpath("test", "fixtures", "mgmfrm_tam_direct_agreement_post_execution_review_packet.json"))
    if !isempty(mgmfrm_tam_direct_agreement_post_execution_review_packet_fixture)
        check_mgmfrm_tam_direct_agreement_post_execution_review_packet_fixture(
            mgmfrm_tam_direct_agreement_post_execution_review_packet_fixture,
        )
    end
    mgmfrm_literature_anchored_independent_review_packet_fixture = optional_fixture_path("MFRM_MGMFRM_LITERATURE_ANCHORED_INDEPENDENT_REVIEW_PACKET_FIXTURE", joinpath("test", "fixtures", "mgmfrm_literature_anchored_independent_review_packet.json"))
    if !isempty(mgmfrm_literature_anchored_independent_review_packet_fixture)
        check_mgmfrm_literature_anchored_independent_review_packet_fixture(
            mgmfrm_literature_anchored_independent_review_packet_fixture,
        )
    end
    mgmfrm_q_candidate_real_fit_diagnostic_linkage_fixture = optional_fixture_path("MFRM_MGMFRM_Q_CANDIDATE_REAL_FIT_DIAGNOSTIC_LINKAGE_FIXTURE", joinpath("test", "fixtures", "mgmfrm_q_candidate_real_fit_diagnostic_linkage.json"))
    if !isempty(mgmfrm_q_candidate_real_fit_diagnostic_linkage_fixture)
        check_mgmfrm_q_candidate_real_fit_diagnostic_linkage_fixture(
            mgmfrm_q_candidate_real_fit_diagnostic_linkage_fixture,
        )
    end
    mgmfrm_q_revision_cross_validation_policy_fixture = optional_fixture_path("MFRM_MGMFRM_Q_REVISION_CROSS_VALIDATION_POLICY_FIXTURE", joinpath("test", "fixtures", "mgmfrm_q_revision_cross_validation_policy.json"))
    if !isempty(mgmfrm_q_revision_cross_validation_policy_fixture)
        check_mgmfrm_q_revision_cross_validation_policy_fixture(
            mgmfrm_q_revision_cross_validation_policy_fixture,
        )
    end
    mgmfrm_q_revision_construct_validity_review_fixture = optional_fixture_path("MFRM_MGMFRM_Q_REVISION_CONSTRUCT_VALIDITY_REVIEW_FIXTURE", joinpath("test", "fixtures", "mgmfrm_q_revision_construct_validity_review.json"))
    if !isempty(mgmfrm_q_revision_construct_validity_review_fixture)
        check_mgmfrm_q_revision_construct_validity_review_fixture(
            mgmfrm_q_revision_construct_validity_review_fixture,
        )
    end
    mgmfrm_guarded_local_fit_entrypoint_fixture = optional_fixture_path("MFRM_MGMFRM_GUARDED_LOCAL_FIT_ENTRYPOINT_FIXTURE", joinpath("test", "fixtures", "mgmfrm_guarded_local_fit_entrypoint.json"))
    if !isempty(mgmfrm_guarded_local_fit_entrypoint_fixture)
        check_mgmfrm_guarded_local_fit_entrypoint_fixture(
            mgmfrm_guarded_local_fit_entrypoint_fixture,
        )
    end
    mgmfrm_fit_metric_threshold_sensitivity_fixture = optional_fixture_path("MFRM_MGMFRM_FIT_METRIC_THRESHOLD_SENSITIVITY_FIXTURE", joinpath("test", "fixtures", "mgmfrm_fit_metric_threshold_sensitivity.json"))
    if !isempty(mgmfrm_fit_metric_threshold_sensitivity_fixture)
        check_mgmfrm_fit_metric_threshold_sensitivity_fixture(
            mgmfrm_fit_metric_threshold_sensitivity_fixture,
        )
    end
    mgmfrm_construct_reviewed_q_fit_reporting_policy_fixture = optional_fixture_path("MFRM_MGMFRM_CONSTRUCT_REVIEWED_Q_FIT_REPORTING_POLICY_FIXTURE", joinpath("test", "fixtures", "mgmfrm_construct_reviewed_q_fit_reporting_policy.json"))
    if !isempty(mgmfrm_construct_reviewed_q_fit_reporting_policy_fixture)
        check_mgmfrm_construct_reviewed_q_fit_reporting_policy_fixture(
            mgmfrm_construct_reviewed_q_fit_reporting_policy_fixture,
        )
    end
    mgmfrm_heldout_prediction_validation_policy_fixture = optional_fixture_path("MFRM_MGMFRM_HELDOUT_PREDICTION_VALIDATION_POLICY_FIXTURE", joinpath("test", "fixtures", "mgmfrm_heldout_prediction_validation_policy.json"))
    if !isempty(mgmfrm_heldout_prediction_validation_policy_fixture)
        check_mgmfrm_heldout_prediction_validation_policy_fixture(
            mgmfrm_heldout_prediction_validation_policy_fixture,
        )
    end
    mgmfrm_validation_split_model_comparison_policy_fixture = optional_fixture_path("MFRM_MGMFRM_VALIDATION_SPLIT_MODEL_COMPARISON_POLICY_FIXTURE", joinpath("test", "fixtures", "mgmfrm_validation_split_model_comparison_policy.json"))
    if !isempty(mgmfrm_validation_split_model_comparison_policy_fixture)
        check_mgmfrm_validation_split_model_comparison_policy_fixture(
            mgmfrm_validation_split_model_comparison_policy_fixture,
        )
    end
    mgmfrm_heldout_prediction_simulation_grid_fixture = optional_fixture_path("MFRM_MGMFRM_HELDOUT_PREDICTION_SIMULATION_GRID_FIXTURE", joinpath("test", "fixtures", "mgmfrm_heldout_prediction_simulation_grid.json"))
    if !isempty(mgmfrm_heldout_prediction_simulation_grid_fixture)
        check_mgmfrm_heldout_prediction_simulation_grid_fixture(
            mgmfrm_heldout_prediction_simulation_grid_fixture,
        )
    end
    mgmfrm_heldout_prediction_execution_fixture = optional_fixture_path("MFRM_MGMFRM_HELDOUT_PREDICTION_EXECUTION_FIXTURE", joinpath("test", "fixtures", "mgmfrm_heldout_prediction_execution.json"))
    if !isempty(mgmfrm_heldout_prediction_execution_fixture)
        check_mgmfrm_heldout_prediction_execution_fixture(
            mgmfrm_heldout_prediction_execution_fixture,
        )
    end
    mgmfrm_full_heldout_refit_review_fixture = optional_fixture_path("MFRM_MGMFRM_FULL_HELDOUT_REFIT_OR_CONSTRUCT_VALIDATION_REVIEW_FIXTURE", joinpath("test", "fixtures", "mgmfrm_full_heldout_refit_or_construct_validation_review.json"))
    if !isempty(mgmfrm_full_heldout_refit_review_fixture)
        check_mgmfrm_full_heldout_refit_or_construct_validation_review_fixture(
            mgmfrm_full_heldout_refit_review_fixture,
        )
    end
    mgmfrm_full_heldout_mcmc_refit_execution_plan_fixture = optional_fixture_path("MFRM_MGMFRM_FULL_HELDOUT_MCMC_REFIT_EXECUTION_PLAN_FIXTURE", joinpath("test", "fixtures", "mgmfrm_full_heldout_mcmc_refit_execution_plan.json"))
    if !isempty(mgmfrm_full_heldout_mcmc_refit_execution_plan_fixture)
        check_mgmfrm_full_heldout_mcmc_refit_execution_plan_fixture(
            mgmfrm_full_heldout_mcmc_refit_execution_plan_fixture,
        )
    end
    mgmfrm_full_heldout_mcmc_refit_batch_smoke_fixture = optional_fixture_path("MFRM_MGMFRM_FULL_HELDOUT_MCMC_REFIT_BATCH_SMOKE_FIXTURE", joinpath("test", "fixtures", "mgmfrm_full_heldout_mcmc_refit_batch_smoke.json"))
    if !isempty(mgmfrm_full_heldout_mcmc_refit_batch_smoke_fixture)
        check_mgmfrm_full_heldout_mcmc_refit_batch_smoke_fixture(
            mgmfrm_full_heldout_mcmc_refit_batch_smoke_fixture,
        )
    end
    mgmfrm_full_heldout_mcmc_refit_fold1_pilot_fixture = optional_fixture_path("MFRM_MGMFRM_FULL_HELDOUT_MCMC_REFIT_FOLD1_PILOT_FIXTURE", joinpath("test", "fixtures", "mgmfrm_full_heldout_mcmc_refit_fold1_pilot.json"))
    if !isempty(mgmfrm_full_heldout_mcmc_refit_fold1_pilot_fixture)
        check_mgmfrm_full_heldout_mcmc_refit_fold1_pilot_fixture(
            mgmfrm_full_heldout_mcmc_refit_fold1_pilot_fixture,
        )
    end
    mgmfrm_full_heldout_mcmc_refit_fold1_scoring_fixture = optional_fixture_path("MFRM_MGMFRM_FULL_HELDOUT_MCMC_REFIT_FOLD1_SCORING_FIXTURE", joinpath("test", "fixtures", "mgmfrm_full_heldout_mcmc_refit_fold1_scoring.json"))
    if !isempty(mgmfrm_full_heldout_mcmc_refit_fold1_scoring_fixture)
        check_mgmfrm_full_heldout_mcmc_refit_fold1_scoring_fixture(
            mgmfrm_full_heldout_mcmc_refit_fold1_scoring_fixture,
        )
    end
    mgmfrm_full_heldout_mcmc_refit_candidate_batch_scoring_fixture = optional_fixture_path("MFRM_MGMFRM_FULL_HELDOUT_MCMC_REFIT_CANDIDATE_BATCH_SCORING_FIXTURE", joinpath("test", "fixtures", "mgmfrm_full_heldout_mcmc_refit_candidate_batch_scoring.json"))
    if !isempty(mgmfrm_full_heldout_mcmc_refit_candidate_batch_scoring_fixture)
        check_mgmfrm_full_heldout_mcmc_refit_candidate_batch_scoring_fixture(
            mgmfrm_full_heldout_mcmc_refit_candidate_batch_scoring_fixture,
        )
    end
    mgmfrm_full_heldout_mcmc_refit_anchor_scoring_fixture = optional_fixture_path("MFRM_MGMFRM_FULL_HELDOUT_MCMC_REFIT_ANCHOR_SCORING_FIXTURE", joinpath("test", "fixtures", "mgmfrm_full_heldout_mcmc_refit_anchor_scoring.json"))
    if !isempty(mgmfrm_full_heldout_mcmc_refit_anchor_scoring_fixture)
        check_mgmfrm_full_heldout_mcmc_refit_anchor_scoring_fixture(
            mgmfrm_full_heldout_mcmc_refit_anchor_scoring_fixture,
        )
    end
    mgmfrm_publication_grade_refit_gate_fixture = optional_fixture_path("MFRM_MGMFRM_PUBLICATION_GRADE_REFIT_GATE_FIXTURE", joinpath("test", "fixtures", "mgmfrm_publication_grade_refit_gate.json"))
    if !isempty(mgmfrm_publication_grade_refit_gate_fixture)
        check_mgmfrm_publication_grade_refit_gate_fixture(
            mgmfrm_publication_grade_refit_gate_fixture,
        )
    end
    mgmfrm_publication_grade_refit_pilot_plan_fixture = optional_fixture_path("MFRM_MGMFRM_PUBLICATION_GRADE_REFIT_PILOT_PLAN_FIXTURE", joinpath("test", "fixtures", "mgmfrm_publication_grade_refit_pilot_plan.json"))
    if !isempty(mgmfrm_publication_grade_refit_pilot_plan_fixture)
        check_mgmfrm_publication_grade_refit_pilot_plan_fixture(
            mgmfrm_publication_grade_refit_pilot_plan_fixture,
        )
    end
    mgmfrm_publication_grade_refit_pilot_execution_harness_fixture = optional_fixture_path("MFRM_MGMFRM_PUBLICATION_GRADE_REFIT_PILOT_EXECUTION_HARNESS_FIXTURE", joinpath("test", "fixtures", "mgmfrm_publication_grade_refit_pilot_execution_harness.json"))
    if !isempty(mgmfrm_publication_grade_refit_pilot_execution_harness_fixture)
        check_mgmfrm_publication_grade_refit_pilot_execution_harness_fixture(
            mgmfrm_publication_grade_refit_pilot_execution_harness_fixture,
        )
    end
    mgmfrm_publication_grade_refit_pilot_results_review_fixture = optional_fixture_path("MFRM_MGMFRM_PUBLICATION_GRADE_REFIT_PILOT_RESULTS_REVIEW_FIXTURE", joinpath("test", "fixtures", "mgmfrm_publication_grade_refit_pilot_results_review.json"))
    if !isempty(mgmfrm_publication_grade_refit_pilot_results_review_fixture)
        check_mgmfrm_publication_grade_refit_pilot_results_review_fixture(
            mgmfrm_publication_grade_refit_pilot_results_review_fixture,
        )
    end
    mgmfrm_publication_grade_refit_brms_like_single_cell_execution_review_fixture = optional_fixture_path("MFRM_MGMFRM_PUBLICATION_GRADE_REFIT_BRMS_LIKE_SINGLE_CELL_EXECUTION_REVIEW_FIXTURE", joinpath("test", "fixtures", "mgmfrm_publication_grade_refit_brms_like_single_cell_execution_review.json"))
    if !isempty(mgmfrm_publication_grade_refit_brms_like_single_cell_execution_review_fixture)
        check_mgmfrm_publication_grade_refit_brms_like_single_cell_execution_review_fixture(
            mgmfrm_publication_grade_refit_brms_like_single_cell_execution_review_fixture,
        )
    end
    mgmfrm_publication_grade_refit_brms_like_pilot_execution_review_fixture = optional_fixture_path("MFRM_MGMFRM_PUBLICATION_GRADE_REFIT_BRMS_LIKE_PILOT_EXECUTION_REVIEW_FIXTURE", joinpath("test", "fixtures", "mgmfrm_publication_grade_refit_brms_like_pilot_execution_review.json"))
    if !isempty(mgmfrm_publication_grade_refit_brms_like_pilot_execution_review_fixture)
        check_mgmfrm_publication_grade_refit_brms_like_pilot_execution_review_fixture(
            mgmfrm_publication_grade_refit_brms_like_pilot_execution_review_fixture,
        )
    end
    mgmfrm_publication_grade_refit_brms_like_scalar_remediation_review_fixture = optional_fixture_path("MFRM_MGMFRM_PUBLICATION_GRADE_REFIT_BRMS_LIKE_SCALAR_REMEDIATION_REVIEW_FIXTURE", joinpath("test", "fixtures", "mgmfrm_publication_grade_refit_brms_like_scalar_remediation_review.json"))
    if !isempty(mgmfrm_publication_grade_refit_brms_like_scalar_remediation_review_fixture)
        check_mgmfrm_publication_grade_refit_brms_like_scalar_remediation_review_fixture(
            mgmfrm_publication_grade_refit_brms_like_scalar_remediation_review_fixture,
        )
    end
    mgmfrm_publication_grade_refit_sampler_remediation_review_fixture = optional_fixture_path("MFRM_MGMFRM_PUBLICATION_GRADE_REFIT_SAMPLER_REMEDIATION_REVIEW_FIXTURE", joinpath("test", "fixtures", "mgmfrm_publication_grade_refit_sampler_remediation_review.json"))
    if !isempty(mgmfrm_publication_grade_refit_sampler_remediation_review_fixture)
        check_mgmfrm_publication_grade_refit_sampler_remediation_review_fixture(
            mgmfrm_publication_grade_refit_sampler_remediation_review_fixture,
        )
    end
    mgmfrm_publication_grade_refit_scalar_remediation_comparison_fixture = optional_fixture_path("MFRM_MGMFRM_PUBLICATION_GRADE_REFIT_SCALAR_REMEDIATION_COMPARISON_FIXTURE", joinpath("test", "fixtures", "mgmfrm_publication_grade_refit_scalar_remediation_comparison.json"))
    if !isempty(mgmfrm_publication_grade_refit_scalar_remediation_comparison_fixture)
        check_mgmfrm_publication_grade_refit_scalar_remediation_comparison_fixture(
            mgmfrm_publication_grade_refit_scalar_remediation_comparison_fixture,
        )
    end
    mgmfrm_publication_grade_refit_batch_expansion_plan_fixture = optional_fixture_path("MFRM_MGMFRM_PUBLICATION_GRADE_REFIT_BATCH_EXPANSION_PLAN_FIXTURE", joinpath("test", "fixtures", "mgmfrm_publication_grade_refit_batch_expansion_plan.json"))
    if !isempty(mgmfrm_publication_grade_refit_batch_expansion_plan_fixture)
        check_mgmfrm_publication_grade_refit_batch_expansion_plan_fixture(
            mgmfrm_publication_grade_refit_batch_expansion_plan_fixture,
        )
    end
    mgmfrm_publication_grade_refit_batch_smoke_execution_review_fixture = optional_fixture_path("MFRM_MGMFRM_PUBLICATION_GRADE_REFIT_BATCH_SMOKE_EXECUTION_REVIEW_FIXTURE", joinpath("test", "fixtures", "mgmfrm_publication_grade_refit_batch_smoke_execution_review.json"))
    if !isempty(mgmfrm_publication_grade_refit_batch_smoke_execution_review_fixture)
        check_mgmfrm_publication_grade_refit_batch_smoke_execution_review_fixture(
            mgmfrm_publication_grade_refit_batch_smoke_execution_review_fixture,
        )
    end
    mgmfrm_publication_grade_refit_well_specified_scenario_execution_review_fixture = optional_fixture_path("MFRM_MGMFRM_PUBLICATION_GRADE_REFIT_WELL_SPECIFIED_SCENARIO_EXECUTION_REVIEW_FIXTURE", joinpath("test", "fixtures", "mgmfrm_publication_grade_refit_well_specified_scenario_execution_review.json"))
    if !isempty(mgmfrm_publication_grade_refit_well_specified_scenario_execution_review_fixture)
        check_mgmfrm_publication_grade_refit_well_specified_scenario_execution_review_fixture(
            mgmfrm_publication_grade_refit_well_specified_scenario_execution_review_fixture,
        )
    end
    mgmfrm_publication_grade_refit_batch_results_review_fixture = optional_fixture_path("MFRM_MGMFRM_PUBLICATION_GRADE_REFIT_BATCH_RESULTS_REVIEW_FIXTURE", joinpath("test", "fixtures", "mgmfrm_publication_grade_refit_batch_results_review.json"))
    if !isempty(mgmfrm_publication_grade_refit_batch_results_review_fixture)
        check_mgmfrm_publication_grade_refit_batch_results_review_fixture(
            mgmfrm_publication_grade_refit_batch_results_review_fixture,
        )
    end
    mgmfrm_publication_grade_threshold_model_weight_policy_review_fixture = optional_fixture_path("MFRM_MGMFRM_PUBLICATION_GRADE_THRESHOLD_MODEL_WEIGHT_POLICY_REVIEW_FIXTURE", joinpath("test", "fixtures", "mgmfrm_publication_grade_threshold_model_weight_policy_review.json"))
    if !isempty(mgmfrm_publication_grade_threshold_model_weight_policy_review_fixture)
        check_mgmfrm_publication_grade_threshold_model_weight_policy_review_fixture(
            mgmfrm_publication_grade_threshold_model_weight_policy_review_fixture,
        )
    end
    mgmfrm_external_construct_dataset_and_independent_public_scope_review_fixture = optional_fixture_path("MFRM_MGMFRM_EXTERNAL_CONSTRUCT_DATASET_AND_INDEPENDENT_PUBLIC_SCOPE_REVIEW_FIXTURE", joinpath("test", "fixtures", "mgmfrm_external_construct_dataset_and_independent_public_scope_review.json"))
    if !isempty(mgmfrm_external_construct_dataset_and_independent_public_scope_review_fixture)
        check_mgmfrm_external_construct_dataset_and_independent_public_scope_review_fixture(
            mgmfrm_external_construct_dataset_and_independent_public_scope_review_fixture,
        )
    end
    mgmfrm_external_construct_attachment_intake_preflight_fixture = optional_fixture_path("MFRM_MGMFRM_EXTERNAL_CONSTRUCT_ATTACHMENT_INTAKE_PREFLIGHT_FIXTURE", joinpath("test", "fixtures", "mgmfrm_external_construct_attachment_intake_preflight.json"))
    if !isempty(mgmfrm_external_construct_attachment_intake_preflight_fixture)
        check_mgmfrm_external_construct_attachment_intake_preflight_fixture(
            mgmfrm_external_construct_attachment_intake_preflight_fixture,
        )
    end
    mgmfrm_external_construct_attachment_request_packet_fixture = optional_fixture_path("MFRM_MGMFRM_EXTERNAL_CONSTRUCT_ATTACHMENT_REQUEST_PACKET_FIXTURE", joinpath("test", "fixtures", "mgmfrm_external_construct_attachment_request_packet.json"))
    if !isempty(mgmfrm_external_construct_attachment_request_packet_fixture)
        check_mgmfrm_external_construct_attachment_request_packet_fixture(
            mgmfrm_external_construct_attachment_request_packet_fixture,
        )
    end
    mgmfrm_fit_threshold_q_heldout_linkage_fixture = optional_fixture_path("MFRM_MGMFRM_FIT_THRESHOLD_Q_HELDOUT_LINKAGE_FIXTURE", joinpath("test", "fixtures", "mgmfrm_fit_threshold_q_heldout_linkage.json"))
    if !isempty(mgmfrm_fit_threshold_q_heldout_linkage_fixture)
        check_mgmfrm_fit_threshold_q_heldout_linkage_fixture(
            mgmfrm_fit_threshold_q_heldout_linkage_fixture,
        )
    end
    mgmfrm_uto_style_retained_draw_budget_guidance_fixture = optional_fixture_path("MFRM_MGMFRM_UTO_STYLE_RETAINED_DRAW_BUDGET_GUIDANCE_FIXTURE", joinpath("test", "fixtures", "mgmfrm_uto_style_retained_draw_budget_guidance.json"))
    if !isempty(mgmfrm_uto_style_retained_draw_budget_guidance_fixture)
        check_mgmfrm_uto_style_retained_draw_budget_guidance_fixture(
            mgmfrm_uto_style_retained_draw_budget_guidance_fixture,
        )
    end
    mgmfrm_recommended_budget_empirical_gate_fixture = optional_fixture_path("MFRM_MGMFRM_RECOMMENDED_BUDGET_EMPIRICAL_GATE_FIXTURE", joinpath("test", "fixtures", "mgmfrm_recommended_budget_empirical_gate.json"))
    if !isempty(mgmfrm_recommended_budget_empirical_gate_fixture)
        check_mgmfrm_recommended_budget_empirical_gate_fixture(
            mgmfrm_recommended_budget_empirical_gate_fixture,
        )
    end
    mgmfrm_construct_reviewed_revised_q_extended_budget_followup_fixture = optional_fixture_path("MFRM_MGMFRM_CONSTRUCT_REVIEWED_REVISED_Q_EXTENDED_BUDGET_FOLLOWUP_FIXTURE", joinpath("test", "fixtures", "mgmfrm_construct_reviewed_revised_q_extended_budget_followup.json"))
    if !isempty(mgmfrm_construct_reviewed_revised_q_extended_budget_followup_fixture)
        check_mgmfrm_construct_reviewed_revised_q_extended_budget_followup_fixture(
            mgmfrm_construct_reviewed_revised_q_extended_budget_followup_fixture,
        )
    end
    mgmfrm_construct_reviewed_revised_q_1000_draw_scenario_replication_fixture = optional_fixture_path("MFRM_MGMFRM_CONSTRUCT_REVIEWED_REVISED_Q_1000_DRAW_SCENARIO_REPLICATION_FIXTURE", joinpath("test", "fixtures", "mgmfrm_construct_reviewed_revised_q_1000_draw_scenario_replication.json"))
    if !isempty(mgmfrm_construct_reviewed_revised_q_1000_draw_scenario_replication_fixture)
        check_mgmfrm_construct_reviewed_revised_q_1000_draw_scenario_replication_fixture(
            mgmfrm_construct_reviewed_revised_q_1000_draw_scenario_replication_fixture,
        )
    end
    mgmfrm_construct_reviewed_revised_q_1000_draw_geometry_branch_expansion_fixture = optional_fixture_path("MFRM_MGMFRM_CONSTRUCT_REVIEWED_REVISED_Q_1000_DRAW_GEOMETRY_BRANCH_EXPANSION_FIXTURE", joinpath("test", "fixtures", "mgmfrm_construct_reviewed_revised_q_1000_draw_geometry_branch_expansion.json"))
    if !isempty(mgmfrm_construct_reviewed_revised_q_1000_draw_geometry_branch_expansion_fixture)
        check_mgmfrm_construct_reviewed_revised_q_1000_draw_geometry_branch_expansion_fixture(
            mgmfrm_construct_reviewed_revised_q_1000_draw_geometry_branch_expansion_fixture,
        )
    end
    mgmfrm_guarded_fit_method_wiring_fixture = optional_fixture_path("MFRM_MGMFRM_GUARDED_FIT_METHOD_WIRING_FIXTURE", joinpath("test", "fixtures", "mgmfrm_guarded_fit_method_wiring.json"))
    if !isempty(mgmfrm_guarded_fit_method_wiring_fixture)
        check_mgmfrm_guarded_fit_method_wiring_fixture(
            mgmfrm_guarded_fit_method_wiring_fixture,
        )
    end
    mgmfrm_guarded_fit_validation_grid_fixture = optional_fixture_path("MFRM_MGMFRM_GUARDED_FIT_VALIDATION_GRID_FIXTURE", joinpath("test", "fixtures", "mgmfrm_guarded_fit_validation_grid.json"))
    if !isempty(mgmfrm_guarded_fit_validation_grid_fixture)
        check_mgmfrm_guarded_fit_validation_grid_fixture(
            mgmfrm_guarded_fit_validation_grid_fixture,
        )
    end
    mgmfrm_guarded_fit_api_dry_run_fixture = optional_fixture_path("MFRM_MGMFRM_GUARDED_FIT_API_DRY_RUN_FIXTURE", joinpath("test", "fixtures", "mgmfrm_guarded_fit_api_dry_run.json"))
    if !isempty(mgmfrm_guarded_fit_api_dry_run_fixture)
        check_mgmfrm_guarded_fit_api_dry_run_fixture(
            mgmfrm_guarded_fit_api_dry_run_fixture,
        )
    end
    mgmfrm_guarded_fit_public_exposure_review_fixture = optional_fixture_path(
        "MFRM_MGMFRM_GUARDED_FIT_PUBLIC_EXPOSURE_REVIEW_FIXTURE",
        joinpath("test", "fixtures", "mgmfrm_guarded_fit_public_exposure_review.json"))
    if !isempty(mgmfrm_guarded_fit_public_exposure_review_fixture)
        check_mgmfrm_guarded_fit_public_exposure_review_fixture(
            mgmfrm_guarded_fit_public_exposure_review_fixture,
        )
    end
    @test_throws ArgumentError LogDensityProblems.logdensity(mgmfrm_target, mgmfrm_raw_params[1:end-1])
    @test_throws ArgumentError LogDensityProblems.logdensity(mgmfrm_target, fill(Inf, mgmfrm_raw_blueprint.n_parameters))
    @test length(mgmfrm_source_values) == length(mgmfrm_predictors)
    @test all(row -> row.kernel === :mgmfrm_source_aligned, mgmfrm_source_values)
    @test all(row -> row.fixture_only && !row.fit_ready, mgmfrm_source_values)
    mgmfrm_row2_values = [0.0, 1.36 * (0.65 - 0.3), 1.36 * (0.65 - 0.3) + 1.36 * (0.65 - (-0.3))]
    mgmfrm_row2_value = only(filter(row -> row.row == 2 && row.category == 1, mgmfrm_source_values))
    @test mgmfrm_row2_value.observed
    @test mgmfrm_row2_value.person_values ≈ [0.2, -0.1]
    @test mgmfrm_row2_value.active_dimensions == [1]
    @test mgmfrm_row2_value.active_dimension_values ≈ [0.2]
    @test mgmfrm_row2_value.item_dimension_discrimination_values ≈ [1.5]
    @test mgmfrm_row2_value.ability_score ≈ 0.3
    @test mgmfrm_row2_value.rater_value ≈ -0.15
    @test mgmfrm_row2_value.item_value ≈ -0.2
    @test mgmfrm_row2_value.rater_consistency_value ≈ 0.8
    @test mgmfrm_row2_value.source_scale ≈ 1.7
    @test mgmfrm_row2_value.scale_value ≈ 1.36
    @test mgmfrm_row2_value.location_value ≈ 0.65
    @test mgmfrm_row2_value.step_values ≈ [0.3]
    @test mgmfrm_row2_value.step_sum ≈ 0.3
    @test mgmfrm_row2_value.scaled_step_sum ≈ 0.408
    @test mgmfrm_row2_value.eta ≈ mgmfrm_row2_values[2]
    @test mgmfrm_row2_value.log_probability ≈ mgmfrm_row2_values[2] - test_logsumexp(mgmfrm_row2_values)
    mgmfrm_row3_values = [0.0, 2.125 * (-0.32 - (-0.2)), 2.125 * (-0.32 - (-0.2)) + 2.125 * (-0.32 - 0.2)]
    mgmfrm_row3_value = only(filter(row -> row.row == 3 && row.category == 2, mgmfrm_source_values))
    @test mgmfrm_row3_value.observed
    @test mgmfrm_row3_value.active_dimensions == [2]
    @test mgmfrm_row3_value.active_dimension_values ≈ [-0.1]
    @test mgmfrm_row3_value.item_dimension_discrimination_values ≈ [0.7]
    @test mgmfrm_row3_value.ability_score ≈ -0.07
    @test mgmfrm_row3_value.rater_value ≈ 0.15
    @test mgmfrm_row3_value.item_value ≈ 0.1
    @test mgmfrm_row3_value.scale_value ≈ 2.125
    @test mgmfrm_row3_value.location_value ≈ -0.32
    @test mgmfrm_row3_value.step_values ≈ [-0.2, 0.2]
    @test mgmfrm_row3_value.step_sum ≈ 0.0
    @test mgmfrm_row3_value.eta ≈ mgmfrm_row3_values[3]
    @test mgmfrm_row3_value.log_probability ≈ mgmfrm_row3_values[3] - test_logsumexp(mgmfrm_row3_values)
    @test [row.log_probability for row in filter(row -> row.observed, mgmfrm_source_values)] ≈
        mgmfrm_source_pointwise
    bad_mgmfrm_rater_sum = copy(mgmfrm_params)
    bad_mgmfrm_rater_sum[5] = 0.2
    @test_throws ArgumentError BayesianMGMFRM._mgmfrm_source_fixture_values(mgmfrm_preview, bad_mgmfrm_rater_sum)
    bad_mgmfrm_discrimination = copy(mgmfrm_params)
    bad_mgmfrm_discrimination[9] = -0.1
    @test_throws ArgumentError BayesianMGMFRM._mgmfrm_source_fixture_values(mgmfrm_preview, bad_mgmfrm_discrimination)
    bad_mgmfrm_consistency = copy(mgmfrm_params)
    bad_mgmfrm_consistency[11] = 1.1
    @test_throws ArgumentError BayesianMGMFRM._mgmfrm_source_fixture_values(mgmfrm_preview, bad_mgmfrm_consistency)
    @test_throws ArgumentError BayesianMGMFRM._mgmfrm_source_fixture_values(gmfrm_preview, mgmfrm_params)
    @test_throws ArgumentError linear_predictor_table(mgmfrm_preview; preview = true)
    @test_throws ArgumentError linear_predictor_values(mgmfrm_spec, zeros(length(mgmfrm_preview.parameter_names)); preview = true)
    @test_throws ArgumentError linear_predictor_values(mgmfrm_preview, zeros(length(mgmfrm_preview.parameter_names)))
    @test_throws ArgumentError predictive_probabilities(mgmfrm_preview, zeros(1, length(mgmfrm_preview.parameter_names)))
    @test_throws ArgumentError design_row_table(mgmfrm_preview; preview = true)
    @test_throws ArgumentError getdesign(mgmfrm_spec)
    @test_throws ArgumentError mfrm_spec(identified_data; family = :mfrm, dimensions = 2)
    @test_throws ArgumentError mfrm_spec(identified_data; family = :gmfrm)
    @test_throws ArgumentError mfrm_spec(identified_data; family = :mgmfrm, dimensions = 2)
    @test_throws ArgumentError mfrm_spec(identified_data; family = :mgmfrm, dimensions = 2, q_matrix = Bool[1; 1])
    @test_throws ArgumentError mfrm_spec(identified_data; q_matrix = q_matrix)

    dff_empty = (
        examinee = ["E1", "E1", "E1", "E2", "E2", "E2"],
        rater = ["R1", "R2", "R1", "R1", "R2", "R1"],
        item = ["I1", "I1", "I2", "I1", "I2", "I2"],
        group = ["A", "A", "A", "A", "B", "A"],
        score = [0, 1, 2, 1, 0, 2],
    )
    dff_data = FacetData(dff_empty;
        person = :examinee,
        rater = :rater,
        item = :item,
        score = :score,
        group = :group)
    plain_dff_report = validate_design(dff_data)
    @test_throws ArgumentError mfrm_spec(
        dff_data;
        thresholds = :partial_credit,
        bias = [(:rater, :group)],
        validation_report = plain_dff_report,
    )
    dff_report = validate_design(dff_data; bias = [(:rater, :group)])
    dff_spec = mfrm_spec(dff_data; thresholds = :partial_credit, validation_report = dff_report)
    @test haskey(dff_spec.validation.dff_counts, (:rater, :group))
    @test dff_spec.validation_bias_terms == [(:rater, :group)]
    @test any(row -> row.block === :dff_rater_group && row.status === :validation_only,
        constraint_table(dff_spec))
    @test dff_spec.validation.dff_counts[(:rater, :group)][("R1", "B")] == 0

    disconnected_same_n = (
        examinee = ["E1", "E1", "E1", "E2", "E2", "E2"],
        rater = ["R1", "R1", "R1", "R2", "R2", "R2"],
        item = ["I1", "I1", "I1", "I2", "I2", "I2"],
        score = [0, 1, 2, 0, 1, 2],
    )
    stale_data = FacetData(disconnected_same_n; person = :examinee, rater = :rater, item = :item, score = :score)
    @test_throws ArgumentError mfrm_spec(stale_data; thresholds = :partial_credit, validation_report = validate_design(identified_data))
end
