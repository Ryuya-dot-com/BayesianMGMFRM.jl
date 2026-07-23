function ld0_cluster_table(;
        n_persons::Int = 3,
        n_testlets::Int = 2,
        n_items::Int = 3,
        n_raters::Int = 2,
        n_occasions::Int = 1,
        one_rater_per_response::Bool = false)
    person_code = String[]
    rater_code = String[]
    item_code = String[]
    score_value = Int[]
    response_code = String[]
    testlet_code = String[]
    task_code = String[]
    wave = String[]
    for person in 1:n_persons, testlet in 1:n_testlets,
            occasion in 1:n_occasions
        raters = one_rater_per_response ?
            (mod(person + testlet + occasion, n_raters) + 1,) : 1:n_raters
        for rater in raters, item in 1:n_items
            push!(person_code, "P$person")
            push!(rater_code, "R$rater")
            push!(item_code, "I$item")
            push!(score_value, mod(person + testlet + occasion + rater + item, 3))
            push!(response_code, "P$(person)-T$(testlet)-O$(occasion)")
            push!(testlet_code, "T$testlet")
            push!(task_code, "Task$testlet")
            push!(wave, "O$occasion")
        end
    end
    return (;
        person_code,
        rater_code,
        item_code,
        score_value,
        response_code,
        testlet_code,
        task_code,
        wave,
    )
end

function ld0_facet_data(table)
    return FacetData(
        table;
        person = :person_code,
        rater = :rater_code,
        item = :item_code,
        score = :score_value,
        response_id = :response_code,
        testlet_id = :testlet_code,
        task = :task_code,
        occasion = :wave,
    )
end

function ld0_permute_table(table, permutation)
    pairs = Pair{Symbol,Any}[]
    for name in propertynames(table)
        push!(pairs, name => getproperty(table, name)[permutation])
    end
    return (; pairs...)
end

@testset "LD0 testlet audit resource and bridge preflight" begin
    data = ld0_facet_data(ld0_cluster_table())
    support = BayesianMGMFRM._testlet_materialized_pair_preflight(
        data;
        max_materialized_pair_rows = 10_000,
    )
    @test support.n_materialized_pair_rows ==
        support.n_diagnostic_candidate_pairs +
        support.n_projected_rater_pairs
    @test support.n_pair_common_unit_links ==
        support.n_single_rating_common_unit_links +
        support.n_within_rater_common_unit_links +
        support.n_rater_common_unit_links
    @test support.n_audit_pair_common_unit_links ==
        support.n_pair_common_unit_links +
        support.n_projected_rater_response_links
    exact = testlet_design_audit(
        data;
        max_materialized_pair_rows = support.n_materialized_pair_rows,
        max_pair_common_unit_links = support.n_audit_pair_common_unit_links,
    )
    @test exact.computational_support == merge(support, (;
        max_materialized_pair_rows = support.n_materialized_pair_rows,
        max_pair_common_unit_links = support.n_audit_pair_common_unit_links,
    ))
    @test_throws ArgumentError testlet_design_audit(
        data;
        max_materialized_pair_rows = support.n_materialized_pair_rows - 1,
    )
    @test_throws ArgumentError testlet_design_audit(
        data;
        max_pair_common_unit_links =
            support.n_audit_pair_common_unit_links - 1,
    )
    @test_throws ArgumentError testlet_design_audit(
        data;
        max_materialized_pair_rows = 0,
    )
    @test_throws ArgumentError testlet_design_audit(
        data;
        max_pair_common_unit_links = 0,
    )

    adjacency = [
        Set([2]),
        Set([1, 3, 4]),
        Set([2, 4]),
        Set([2, 3]),
    ]
    @test BayesianMGMFRM._testlet_graph_bridges(adjacency) == ((1, 2),)
end

@testset "LD0 clustered-response data contract" begin
    table = ld0_cluster_table()
    data = ld0_facet_data(table)
    @test sort(collect(keys(data.optional)); by = string) ==
        [:occasion, :response_id, :task, :testlet_id]
    @test data.optional_levels[:response_id] ==
        Any["P1-T1-O1", "P1-T2-O1", "P2-T1-O1", "P2-T2-O1",
            "P3-T1-O1", "P3-T2-O1"]
    @test data.optional_levels[:testlet_id] == Any["T1", "T2"]

    normalized = facet_response_table(data)
    @test propertynames(normalized) ==
        (:person, :rater, :item, :score, :occasion, :response_id, :task,
            :testlet_id)
    normalized_data = FacetData(
        normalized;
        person = :person,
        rater = :rater,
        item = :item,
        score = :score,
        occasion = :occasion,
        response_id = :response_id,
        task = :task,
        testlet_id = :testlet_id,
    )
    @test facet_response_table(normalized_data) == normalized

    validation = validate_design(data)
    @test validation.passed
    @test !any(issue -> issue.code === :singleton_facet_level &&
        get(issue.context, :facet, nothing) === :response_id, validation.issues)
    testlet_person = coverage_matrix(data;
        rows = :testlet_id,
        columns = :person)
    @test testlet_person.counts == fill(6, 2, 3)
    @test only(rater_overlap(data; unit = :response_id)).shared_units == 6
    @test only(rater_overlap(data; unit = :person_testlet)).shared_units == 6
    @test only(rater_overlap(data; unit = :response_item)).shared_units == 18
    @test_throws ArgumentError rater_overlap(
        FacetData((;
            person = ["P1", "P1"],
            rater = ["R1", "R2"],
            item = ["I1", "I1"],
            score = [0, 1],
        ); person = :person, rater = :rater, item = :item, score = :score);
        unit = :response_id)

    base = FacetData((;
        person_code = table.person_code,
        rater_code = table.rater_code,
        item_code = table.item_code,
        score_value = table.score_value,
    ); person = :person_code, rater = :rater_code, item = :item_code,
        score = :score_value)
    base_design = getdesign(mfrm_spec(base; thresholds = :partial_credit))
    metadata_design = getdesign(mfrm_spec(data; thresholds = :partial_credit))
    @test base_design.parameter_names == metadata_design.parameter_names
    parameters = collect(range(-0.2, 0.2;
        length = length(base_design.parameter_names)))
    @test pointwise_loglikelihood(base_design, parameters) ≈
        pointwise_loglikelihood(metadata_design, parameters)
    @test model_manifest(base).data.data_signature !=
        model_manifest(data).data.data_signature

    reconstructed = BayesianMGMFRM._loo_refit_training_data(
        data,
        collect(1:data.n),
    )
    @test sort(collect(keys(reconstructed.optional)); by = string) ==
        [:occasion, :response_id, :task, :testlet_id]
    @test facet_response_table(reconstructed) == normalized
end

@testset "LD0 testlet design audit" begin
    table = ld0_cluster_table()
    data = ld0_facet_data(table)
    supported = testlet_design_audit(
        data;
        independent_ratings_declared = true,
    )
    @test supported.schema == "bayesianmgmfrm.testlet_design_audit.v1"
    @test supported.status === :ok
    @test supported.schema_valid
    @test supported.structural_identification_supported
    @test supported.candidate_scope_supported
    @test supported.structurally_eligible_for_candidate
    @test supported.structural_profile_met
    @test !supported.current_fit_supported
    @test !supported.any_diagnostic_pair_family_supported
    @test !supported.mechanism_claim_eligible
    @test supported.summary.n_responses == 6
    @test supported.summary.n_testlets == 2
    @test supported.summary.scalar_shared_cluster_structurally_eligible
    @test supported.summary.rater_response_halo_structurally_eligible
    @test supported.summary.rater_task_structurally_eligible
    @test any(row -> row.check === :item_testlet_mapping &&
        row.observed.crossed_items == 3, supported.rows)
    single_support = supported.diagnostic_pair_support.single_rating_item_q3
    within_support = supported.diagnostic_pair_support.within_rater_item_q3
    @test single_support.status === :not_applicable
    @test single_support.inapplicable_reason ===
        :multiple_ratings_or_criterion_split_within_response
    @test within_support.estimation_strata === :testlet_id
    @test isempty(within_support.duplicate_unit_facets)

    diagnostic_custom = testlet_design_audit(
        data;
        min_pair_common_units = 2,
        independent_ratings_declared = true,
    )
    @test diagnostic_custom.support_profile === :custom_unvalidated
    @test diagnostic_custom.any_diagnostic_pair_family_supported
    diagnostic_support = diagnostic_custom.diagnostic_pair_support
    diagnostic_within = diagnostic_support.within_rater_item_q3
    diagnostic_rater = diagnostic_support.rater_on_shared_response_criterion
    @test diagnostic_within.n_eligible_pairs > 0
    @test diagnostic_rater.n_eligible_pairs > 0

    custom_profile = testlet_design_audit(
        data;
        min_persons_per_testlet = 3,
        independent_ratings_declared = true,
    )
    @test custom_profile.support_profile === :custom_unvalidated
    @test !custom_profile.profile_is_frozen
    @test custom_profile.status === :warning
    @test custom_profile.structural_profile_met

    independence_unverified = testlet_design_audit(data)
    @test independence_unverified.status === :warning
    @test independence_unverified.structurally_eligible_for_candidate
    @test !independence_unverified.structural_profile_met
    @test any(row -> row.check === :rater_response_halo_support &&
        row.note === :rating_independence_not_declared,
        independence_unverified.rows)

    changed_scores = merge(table, (; score_value = reverse(table.score_value)))
    changed_audit = testlet_design_audit(
        ld0_facet_data(changed_scores);
        independent_ratings_declared = true,
    )
    @test isequal(changed_audit, supported)
    permutation = reverse(collect(eachindex(table.score_value)))
    permuted_audit = testlet_design_audit(
        ld0_facet_data(ld0_permute_table(table, permutation));
        independent_ratings_declared = true,
    )
    @test isequal(permuted_audit, supported)

    invalid_response = copy(table.response_code)
    invalid_response[end] = table.response_code[1]
    invalid_data = ld0_facet_data(merge(table, (; response_code = invalid_response)))
    invalid_audit = testlet_design_audit(invalid_data)
    @test invalid_audit.status === :error
    @test !invalid_audit.schema_valid
    @test !invalid_audit.structurally_eligible_for_candidate
    @test any(row -> row.check === :response_nesting && row.status === :error,
        invalid_audit.rows)

    duplicate_table = (; (
        name => vcat(getproperty(table, name), first(getproperty(table, name)))
        for name in propertynames(table)
    )...)
    duplicate_audit = testlet_design_audit(ld0_facet_data(duplicate_table))
    @test duplicate_audit.status === :error
    @test duplicate_audit.summary.response_nesting_valid
    @test !duplicate_audit.summary.duplicate_rating_keys_valid
    @test any(row -> row.check === :duplicate_rating_key &&
        row.status === :error, duplicate_audit.rows)

    single_item_rows = findall(==("I1"), table.item_code)
    single_item_audit = testlet_design_audit(
        ld0_facet_data(ld0_permute_table(table, single_item_rows));
        independent_ratings_declared = true,
    )
    @test single_item_audit.status === :underidentified
    @test !single_item_audit.structurally_eligible_for_candidate

    nested_table = ld0_cluster_table(n_persons = 4)
    nested_rows = findall(eachindex(nested_table.person_code)) do row
        person = nested_table.person_code[row]
        testlet = nested_table.testlet_code[row]
        return ((person == "P1" || person == "P2") && testlet == "T1") ||
            ((person == "P3" || person == "P4") && testlet == "T2")
    end
    nested_data = ld0_facet_data(ld0_permute_table(nested_table, nested_rows))
    @test rating_design_audit(nested_data).summary.rating_graph_status ===
        :connected
    nested_audit = testlet_design_audit(
        nested_data;
        independent_ratings_declared = true,
    )
    @test nested_audit.status === :underidentified
    @test nested_audit.summary.person_testlet_graph_components == 2

    single_rater = ld0_facet_data(ld0_cluster_table(
        one_rater_per_response = true,
    ))
    single_rater_scalar = testlet_design_audit(
        single_rater;
        independent_ratings_declared = true,
    )
    @test single_rater_scalar.status === :warning
    @test single_rater_scalar.structurally_eligible_for_candidate
    @test !single_rater_scalar.structural_profile_met
    single_rater_halo = testlet_design_audit(
        single_rater;
        target = :rater_response_halo,
        independent_ratings_declared = true,
    )
    @test single_rater_halo.status === :underidentified
    @test !single_rater_halo.structurally_eligible_for_candidate

    split_halo_table = ld0_cluster_table(n_persons = 3, n_items = 2)
    split_halo_rows = findall(eachindex(split_halo_table.person_code)) do row
        person = split_halo_table.person_code[row]
        testlet = split_halo_table.testlet_code[row]
        rater = split_halo_table.rater_code[row]
        item = split_halo_table.item_code[row]
        return (person == "P1" && rater == "R1") ||
            (person == "P2" && rater == "R2") ||
            (person == "P3" &&
                ((rater == "R1" && item == "I1") ||
                 (rater == "R2" && item == "I2")))
    end
    split_halo_audit = testlet_design_audit(
        ld0_facet_data(ld0_permute_table(split_halo_table, split_halo_rows));
        target = :rater_response_halo,
        independent_ratings_declared = true,
    )
    split_halo_row = only(row for row in split_halo_audit.rows
        if row.check === :rater_response_halo_support)
    @test split_halo_row.observed.observed_multi_rater_responses == 2
    @test split_halo_row.observed.supported_multi_rater_responses == 0
    @test split_halo_audit.status === :underidentified

    bridge_halo_table = ld0_cluster_table(
        n_persons = 2,
        n_items = 2,
        n_raters = 3,
    )
    bridge_halo_rows = findall(eachindex(bridge_halo_table.person_code)) do row
        person = bridge_halo_table.person_code[row]
        testlet = bridge_halo_table.testlet_code[row]
        rater = bridge_halo_table.rater_code[row]
        return (person == "P1" && rater in ("R1", "R2")) ||
            (person == "P2" && testlet == "T1" && rater in ("R2", "R3")) ||
            (person == "P2" && testlet == "T2" && rater == "R3")
    end
    bridge_halo_audit = testlet_design_audit(
        ld0_facet_data(ld0_permute_table(bridge_halo_table, bridge_halo_rows));
        target = :rater_response_halo,
        independent_ratings_declared = true,
    )
    bridge_halo_row = only(row for row in bridge_halo_audit.rows
        if row.check === :rater_response_halo_support)
    @test bridge_halo_row.observed.projected_rater_components == 1
    @test bridge_halo_row.observed.weak_projected_rater_bridges == 1
    @test bridge_halo_audit.status === :underidentified

    task_nested_rows = findall(eachindex(table.person_code)) do row
        return (table.testlet_code[row] == "T1" &&
                table.rater_code[row] == "R1") ||
            (table.testlet_code[row] == "T2" && table.rater_code[row] == "R2")
    end
    task_nested_data = ld0_facet_data(
        ld0_permute_table(table, task_nested_rows),
    )
    task_nested_audit = testlet_design_audit(
        task_nested_data;
        target = :rater_task,
    )
    @test task_nested_audit.status === :underidentified
    @test !task_nested_audit.structurally_eligible_for_candidate

    task_chain_table = ld0_cluster_table(n_testlets = 3)
    task_chain_rows = findall(eachindex(task_chain_table.person_code)) do row
        testlet = task_chain_table.testlet_code[row]
        rater = task_chain_table.rater_code[row]
        return (testlet == "T1" && rater == "R1") ||
            (testlet == "T2") ||
            (testlet == "T3" && rater == "R2")
    end
    task_chain_audit = testlet_design_audit(
        ld0_facet_data(ld0_permute_table(task_chain_table, task_chain_rows));
        target = :rater_task,
    )
    task_chain_row = only(row for row in task_chain_audit.rows
        if row.check === :rater_task_crossing)
    @test task_chain_row.observed.rater_task_components == 1
    @test task_chain_row.observed.tasks_below_rater_minimum == 2
    @test task_chain_audit.status === :underidentified

    unreplicated_task = testlet_design_audit(
        ld0_facet_data(ld0_cluster_table(n_persons = 1));
        target = :rater_task,
    )
    unreplicated_task_row = only(row for row in unreplicated_task.rows
        if row.check === :rater_task_crossing)
    @test unreplicated_task_row.observed.insufficient_rater_task_cells > 0
    @test unreplicated_task.status === :underidentified

    repeated = ld0_facet_data(ld0_cluster_table(n_occasions = 2))
    repeated_audit = testlet_design_audit(
        repeated;
        target = :stable_person_testlet,
        independent_ratings_declared = true,
    )
    @test repeated_audit.status === :warning
    @test repeated_audit.structurally_eligible_for_candidate
    @test repeated_audit.summary.stable_person_testlet_structurally_eligible

    one_testlet_repeated = testlet_design_audit(
        ld0_facet_data(ld0_cluster_table(n_testlets = 1, n_occasions = 2));
        target = :stable_person_testlet,
        independent_ratings_declared = true,
    )
    @test one_testlet_repeated.status === :underidentified
    @test !one_testlet_repeated.structurally_eligible_for_candidate
    scalar_on_repeated = testlet_design_audit(repeated)
    @test scalar_on_repeated.status === :unsupported_candidate
    @test scalar_on_repeated.structural_identification_supported
    @test !scalar_on_repeated.candidate_scope_supported
    @test !scalar_on_repeated.structurally_eligible_for_candidate
    @test !scalar_on_repeated.summary.one_response_per_person_testlet

    q_matrix = Bool[1 0; 0 1; 1 1]
    mgmfrm_spec = mfrm_spec(
        data;
        family = :mgmfrm,
        dimensions = 2,
        q_matrix,
    )
    q_audit = testlet_design_audit(
        mgmfrm_spec;
        target = :mgmfrm_testlet_separation,
    )
    @test q_audit.status === :warning
    @test q_audit.structurally_eligible_for_candidate
    @test q_audit.summary.mgmfrm_testlet_separation_applicable
    @test q_audit.summary.mgmfrm_testlet_separation_structurally_eligible

    q_disconnected_spec = mfrm_spec(
        nested_data;
        family = :mgmfrm,
        dimensions = 2,
        q_matrix,
    )
    q_disconnected_audit = testlet_design_audit(
        q_disconnected_spec;
        target = :mgmfrm_testlet_separation,
    )
    @test q_disconnected_audit.status === :underidentified
    @test !q_disconnected_audit.structurally_eligible_for_candidate
    q_disconnected_row = only(row for row in q_disconnected_audit.rows
        if row.check === :q_by_testlet_support)
    @test q_disconnected_row.observed.person_testlet_graph_components == 2

    q_single_indicator_table = ld0_cluster_table()
    q_single_indicator_rows = findall(
        eachindex(q_single_indicator_table.person_code),
    ) do row
        person_number = parse(Int,
            q_single_indicator_table.person_code[row][2:end])
        testlet_number = parse(Int,
            q_single_indicator_table.testlet_code[row][2:end])
        item_number = mod(person_number + testlet_number - 2, 3) + 1
        q_single_indicator_table.item_code[row] == "I$item_number"
    end
    q_single_indicator_data = ld0_facet_data(ld0_permute_table(
        q_single_indicator_table,
        q_single_indicator_rows,
    ))
    q_single_indicator_spec = mfrm_spec(
        q_single_indicator_data;
        family = :mgmfrm,
        dimensions = 2,
        q_matrix,
    )
    q_single_indicator_audit = testlet_design_audit(
        q_single_indicator_spec;
        target = :mgmfrm_testlet_separation,
    )
    @test q_single_indicator_audit.summary.minimum_response_indicators == 1
    @test q_single_indicator_audit.status === :underidentified
    @test !q_single_indicator_audit.structurally_eligible_for_candidate
    q_single_indicator_row = only(row for row in q_single_indicator_audit.rows
        if row.check === :q_by_testlet_support)
    @test q_single_indicator_row.observed.responses_below_indicator_minimum > 0
    @test !q_single_indicator_row.observed.cluster_base_eligible

    q_nested_table = ld0_cluster_table(n_items = 4)
    q_nested_rows = findall(eachindex(q_nested_table.person_code)) do row
        item = q_nested_table.item_code[row]
        testlet = q_nested_table.testlet_code[row]
        return (testlet == "T1" && item in ("I1", "I2")) ||
            (testlet == "T2" && item in ("I3", "I4"))
    end
    q_nested_data = ld0_facet_data(
        ld0_permute_table(q_nested_table, q_nested_rows),
    )
    q_nested_spec = mfrm_spec(
        q_nested_data;
        family = :mgmfrm,
        dimensions = 2,
        q_matrix = Bool[1 0; 1 0; 0 1; 0 1],
    )
    q_nested_audit = testlet_design_audit(
        q_nested_spec;
        target = :mgmfrm_testlet_separation,
    )
    @test q_nested_audit.status === :underidentified
    @test !q_nested_audit.structurally_eligible_for_candidate

    q_partition_table = ld0_cluster_table(n_testlets = 4, n_items = 4)
    q_partition_rows = findall(eachindex(q_partition_table.person_code)) do row
        testlet = q_partition_table.testlet_code[row]
        item = q_partition_table.item_code[row]
        return (testlet in ("T1", "T2") && item in ("I1", "I2")) ||
            (testlet in ("T3", "T4") && item in ("I3", "I4"))
    end
    q_partition_data = ld0_facet_data(
        ld0_permute_table(q_partition_table, q_partition_rows),
    )
    q_partition_spec = mfrm_spec(
        q_partition_data;
        family = :mgmfrm,
        dimensions = 2,
        q_matrix = Bool[1 0; 1 0; 0 1; 0 1],
    )
    q_partition_audit = testlet_design_audit(
        q_partition_spec;
        target = :mgmfrm_testlet_separation,
    )
    q_partition_row = only(row for row in q_partition_audit.rows
        if row.check === :q_by_testlet_support)
    @test q_partition_row.observed.testlets_per_dimension == [2, 2]
    @test q_partition_row.observed.q_testlet_graph_components == 2
    @test q_partition_audit.status === :underidentified

    disjoint_pair_table = ld0_cluster_table(
        n_persons = 1,
        n_testlets = 2,
        n_items = 4,
        n_raters = 1,
    )
    disjoint_pair_rows = findall(eachindex(disjoint_pair_table.person_code)) do row
        testlet = disjoint_pair_table.testlet_code[row]
        item = disjoint_pair_table.item_code[row]
        return (testlet == "T1" && item in ("I1", "I2")) ||
            (testlet == "T2" && item in ("I3", "I4"))
    end
    disjoint_pair_audit = testlet_design_audit(
        ld0_facet_data(ld0_permute_table(disjoint_pair_table, disjoint_pair_rows)),
    )
    @test !disjoint_pair_audit.any_diagnostic_pair_family_supported
    @test all(support -> support.status in (:sparse, :not_applicable),
        values(disjoint_pair_audit.diagnostic_pair_support))
    disjoint_support = disjoint_pair_audit.diagnostic_pair_support
    @test disjoint_support.single_rating_item_q3.n_pairs == 2
    @test disjoint_support.within_rater_item_q3.n_pairs == 2

    no_metadata = FacetData((;
        person = ["P1", "P1"],
        rater = ["R1", "R1"],
        item = ["I1", "I2"],
        score = [0, 1],
    ); person = :person, rater = :rater, item = :item, score = :score)
    missing_audit = testlet_design_audit(no_metadata)
    @test missing_audit.status === :error
    @test missing_audit.summary.missing_required_roles ==
        (:response_id, :testlet_id)

    @test_throws ArgumentError testlet_design_audit(data; target = :unknown)
    @test_throws ArgumentError testlet_design_audit(data;
        support_profile = :unknown)
    @test_throws ArgumentError testlet_design_audit(data;
        min_indicators_per_response = 0)
end

@testset "LD0 standardized residual smoke" begin
    data = ld0_facet_data(ld0_cluster_table())
    design = getdesign(mfrm_spec(data; thresholds = :partial_credit))
    draws = zeros(2, length(design.parameter_names))
    standardized = predictive_standardized_residuals(design, draws)
    expected = expected_scores(design, draws)
    variances = predictive_variances(design, draws)
    manual = (reshape(Float64.(data.score), 1, :) .- expected) ./ sqrt.(variances)
    @test standardized.schema ==
        "bayesianmgmfrm.predictive_standardized_residuals.v1"
    @test standardized.family === :mfrm
    @test standardized.draw_indices == (1, 2)
    @test standardized.n_valid == length(standardized.valid)
    @test standardized.n_excluded == 0
    @test all(standardized.valid)
    @test standardized.values ≈ manual

    excluded = predictive_standardized_residuals(
        design,
        draws;
        variance_tolerance = 1.0,
    )
    @test excluded.n_valid == 0
    @test excluded.n_excluded == length(excluded.valid)
    @test all(isnan, excluded.values)
    @test all(==(data.n), excluded.excluded_by_draw)
    @test_throws ArgumentError predictive_standardized_residuals(
        design,
        draws;
        variance_tolerance = -1.0,
    )
    @test_throws ArgumentError predictive_standardized_residuals(
        design,
        zeros(0, length(design.parameter_names)),
    )

    fit_result = fit(
        design;
        ndraws = 2,
        warmup = 1,
        chains = 1,
        step_size = 0.02,
        seed = 20260720,
    )
    selected = predictive_standardized_residuals(
        fit_result;
        draw_indices = [2, 1],
    )
    supplied = predictive_standardized_residuals(
        design,
        fit_result.draws[[2, 1], :],
    )
    @test selected.draw_indices == (2, 1)
    @test selected.draw_source === :posterior
    @test selected.values ≈ supplied.values
    @test selected.valid == supplied.valid
    @test_throws ArgumentError predictive_standardized_residuals(
        fit_result;
        ndraws = 1,
        draw_indices = [1],
    )
end
