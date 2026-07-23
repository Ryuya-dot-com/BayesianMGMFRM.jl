@testset "testlet overlap interpretation and refit blocker" begin
    table = let
        person = String[]
        rater = String[]
        item = String[]
        score = Int[]
        response_id = String[]
        testlet_id = String[]
        for p in 1:3, t in 1:2, r in 1:2, i in 1:2
            push!(person, "P$p")
            push!(rater, "R$r")
            push!(item, "I$i")
            push!(score, mod(p + t + r + i, 3))
            push!(response_id, "P$(p)-T$(t)")
            push!(testlet_id, "T$t")
        end
        (; person, rater, item, score, response_id, testlet_id)
    end
    data = FacetData(
        table;
        person = :person,
        rater = :rater,
        item = :item,
        score = :score,
        response_id = :response_id,
        testlet_id = :testlet_id,
    )

    legacy_row = only(rater_overlap(data; unit = :person_item))
    @test propertynames(legacy_row) == (
        :rater_a,
        :rater_b,
        :unit,
        :n_units_a,
        :n_units_b,
        :shared_units,
        :union_units,
        :jaccard,
    )

    for unit in (:testlet_id, :person_testlet)
        row = only(rater_overlap(data; unit))
        @test row.overlap_purpose === :descriptive_coverage
        @test !row.rater_linking_eligible
        @test row.interpretation ===
            :shared_testlet_coverage_does_not_establish_common_response_linking
    end
    for unit in (:response_id, :response_item)
        row = only(rater_overlap(data; unit))
        @test row.overlap_purpose === :common_response_linking
        @test row.rater_linking_eligible
        @test row.interpretation ===
            :shared_response_overlap_can_support_rater_linking
    end

    function linking_guard_message(callable)
        try
            callable()
        catch err
            @test err isa ArgumentError
            return sprint(showerror, err)
        end
        @test false
        return ""
    end

    anchor_message = linking_guard_message(
        () -> anchor_linking_summary(data; unit = :testlet_id),
    )
    @test occursin("descriptive cluster coverage only", anchor_message)
    @test occursin("unit = :response_id or :response_item", anchor_message)
    audit_message = linking_guard_message(
        () -> rating_design_audit(data; unit = :person_testlet),
    )
    @test occursin("descriptive cluster coverage only", audit_message)

    response_linking = anchor_linking_summary(data; unit = :response_id)
    @test response_linking.rater_linking_status === :connected
    response_item_audit = rating_design_audit(data; unit = :response_item)
    @test response_item_audit.summary.rater_linking_status === :connected

    response_plan = kfold_plan(data; k = 2, group_by = :response_id)
    response_diagnostics = kfold_plan_diagnostics(data, response_plan)
    response_rows = filter(
        row -> row.facet === :response_id,
        response_diagnostics.rows,
    )
    @test !response_diagnostics.passed
    @test length(response_rows) == response_plan.n_folds
    @test all(row -> row.refit_blocker, response_rows)
    @test all(row -> row.n_heldout_only_levels > 0, response_rows)

    refit_message = linking_guard_message(
        () -> kfold_refit(data, response_plan),
    )
    @test occursin("heldout-only facet levels", refit_message)
    @test occursin("kfold_plan_diagnostics", refit_message)
end
