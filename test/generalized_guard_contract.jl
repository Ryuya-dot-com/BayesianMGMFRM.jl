@testset "guarded generalized fit contract" begin
    rows = (;
        person = ["P1", "P1", "P1", "P2", "P2", "P2"],
        rater = ["R1", "R2", "R1", "R1", "R2", "R1"],
        item = ["I1", "I1", "I2", "I1", "I2", "I2"],
        group = ["A", "A", "A", "A", "B", "A"],
        score = [0, 1, 2, 1, 0, 2],
    )
    data = FacetData(
        rows;
        person = :person,
        rater = :rater,
        item = :item,
        score = :score,
        group = :group,
    )
    q_matrix = Bool[1 0; 0 1]
    hard_anchor = [(;
        block = :rater,
        level = "R1",
        value = 0.0,
        type = :hard,
    )]

    function guarded_error(f)
        try
            f()
        catch err
            err isa ArgumentError || rethrow()
            return sprint(showerror, err)
        end
        error("expected the guarded generalized contract to reject the request")
    end

    function check_guarded_rejection(message::AbstractString, option::Symbol)
        @test occursin("$option = ", message)
        @test occursin("Supported configuration:", message)
        @test !occursin(r"blocked_option|supported_surface|next_gate|internal_|_SourceFixturePrior",
            message)
        return nothing
    end

    valid_gmfrm = mfrm_spec(
        data;
        family = :gmfrm,
        thresholds = :partial_credit,
        discrimination = :rater,
    )
    valid_mgmfrm = mfrm_spec(
        data;
        family = :mgmfrm,
        dimensions = 2,
        thresholds = :partial_credit,
        discrimination = :none,
        q_matrix,
    )
    @test getdesign(valid_gmfrm; preview = true).spec === valid_gmfrm
    @test getdesign(valid_mgmfrm; preview = true).spec === valid_mgmfrm

    gmfrm_rating_scale = mfrm_spec(
        data;
        family = :gmfrm,
        thresholds = :rating_scale,
        discrimination = :rater,
    )
    gmfrm_anchored = mfrm_spec(
        data;
        family = :gmfrm,
        thresholds = :partial_credit,
        discrimination = :rater,
        anchors = hard_anchor,
    )
    @test getdesign(gmfrm_rating_scale; preview = true).spec === gmfrm_rating_scale
    @test getdesign(gmfrm_anchored; preview = true).spec === gmfrm_anchored
    check_guarded_rejection(guarded_error(() -> fit(
        gmfrm_rating_scale;
        experimental = true,
        ndraws = 1,
        warmup = 0,
    )), :thresholds)
    check_guarded_rejection(guarded_error(() -> fit(
        gmfrm_anchored;
        experimental = true,
        ndraws = 1,
        warmup = 0,
    )), :anchors)
    check_guarded_rejection(guarded_error(() -> fit_cache_key(
        gmfrm_anchored;
        experimental = true,
        backend = :advancedhmc,
        seed = 1,
    )), :anchors)
    check_guarded_rejection(guarded_error(() -> pointwise_loglikelihood_matrix(
        getdesign(gmfrm_rating_scale; preview = true),
        zeros(1, 1);
        parameter_space = :raw,
    )), :thresholds)

    invalid_mgmfrm_specs = (
        thresholds = mfrm_spec(
            data;
            family = :mgmfrm,
            dimensions = 2,
            thresholds = :rating_scale,
            q_matrix,
        ),
        discrimination = mfrm_spec(
            data;
            family = :mgmfrm,
            dimensions = 2,
            thresholds = :partial_credit,
            discrimination = :rater,
            q_matrix,
        ),
        dff_effects = mfrm_spec(
            data;
            family = :mgmfrm,
            dimensions = 2,
            thresholds = :partial_credit,
            discrimination = :none,
            q_matrix,
            bias = [(:rater, :group)],
        ),
        anchors = mfrm_spec(
            data;
            family = :mgmfrm,
            dimensions = 2,
            thresholds = :partial_credit,
            discrimination = :none,
            q_matrix,
            anchors = hard_anchor,
        ),
    )
    for (option, spec) in pairs(invalid_mgmfrm_specs)
        @test getdesign(spec; preview = true).spec === spec
        check_guarded_rejection(guarded_error(() -> fit(
            spec;
            experimental = true,
            ndraws = 1,
            warmup = 0,
        )), option)
    end
    check_guarded_rejection(guarded_error(() -> fit_cache_key(
        invalid_mgmfrm_specs.thresholds;
        experimental = true,
        backend = :advancedhmc,
        seed = 2,
    )), :thresholds)
    check_guarded_rejection(guarded_error(() -> pointwise_loglikelihood_matrix(
        getdesign(invalid_mgmfrm_specs.discrimination; preview = true),
        zeros(1, 1);
        parameter_space = :raw,
    )), :discrimination)
    check_guarded_rejection(guarded_error(() -> fit(
        valid_mgmfrm;
        experimental = true,
        prior = MFRMPrior(),
        ndraws = 1,
        warmup = 0,
    )), :prior)

    mutated_q_spec = mfrm_spec(
        data;
        family = :mgmfrm,
        dimensions = 2,
        thresholds = :partial_credit,
        discrimination = :none,
        q_matrix = copy(q_matrix),
    )
    mutated_q_spec.q_matrix .= false
    check_guarded_rejection(guarded_error(() -> fit(
        mutated_q_spec;
        experimental = true,
        ndraws = 1,
        warmup = 0,
    )), :q_matrix)

    valid_mgmfrm_design = getdesign(valid_mgmfrm; preview = true)
    heldout_score_design = BayesianMGMFRM._loo_refit_score_design(
        data,
        valid_mgmfrm_design,
        [1],
    )
    raw_blueprint =
        BayesianMGMFRM._mgmfrm_source_unconstrained_blueprint(
            valid_mgmfrm_design)
    raw_params = zeros(raw_blueprint.n_parameters)
    direct_params =
        BayesianMGMFRM._mgmfrm_source_constrained_params_from_unconstrained(
            valid_mgmfrm_design,
            raw_params,
        )
    score_q_validation =
        BayesianMGMFRM.q_matrix_validation(heldout_score_design)
    @test !score_q_validation.passed
    @test all(row -> row.severity !== :error ||
            row.check === :dimension_facet_subgraph_coverage,
        score_q_validation.rows)
    @test BayesianMGMFRM._q_matrix_guarded_structure_passed(
        score_q_validation)
    @test !BayesianMGMFRM._q_matrix_guarded_structure_passed((;
        rows = ((; check = :future_unclassified_q_check,
            severity = :error),),
    ))
    @test_throws ArgumentError BayesianMGMFRM._mgmfrm_source_pointwise_loglikelihood(
        heldout_score_design,
        direct_params,
    )
    heldout_loglikelihood =
        BayesianMGMFRM._mgmfrm_source_pointwise_loglikelihood(
            heldout_score_design,
            direct_params;
            require_q_observation_coverage = false,
        )
    @test length(heldout_loglikelihood) == 1
    @test all(isfinite, heldout_loglikelihood)
    mutated_heldout_spec = mfrm_spec(
        data;
        family = :mgmfrm,
        dimensions = 2,
        thresholds = :partial_credit,
        discrimination = :none,
        q_matrix = copy(q_matrix),
    )
    mutated_heldout_score_design = BayesianMGMFRM._loo_refit_score_design(
        data,
        getdesign(mutated_heldout_spec; preview = true),
        [1],
    )
    mutated_heldout_score_design.spec.q_matrix[:, 2] .= false
    check_guarded_rejection(guarded_error(() ->
        BayesianMGMFRM._mgmfrm_source_pointwise_loglikelihood(
            mutated_heldout_score_design,
            direct_params;
            require_q_observation_coverage = false,
        )), :q_matrix)

    ladder = model_ladder()
    gmfrm_surface = only(row for row in ladder
        if row.scope === :scalar_gmfrm_guarded_experimental)
    mgmfrm_surface = only(row for row in ladder
        if row.scope === :fixed_q_confirmatory_mgmfrm_guarded_experimental)
    @test gmfrm_surface.threshold_regimes == (:partial_credit,)
    @test gmfrm_surface.spec_discrimination == (:rater,)
    @test mgmfrm_surface.threshold_regimes == (:partial_credit,)
    @test mgmfrm_surface.spec_discrimination == (:none,)
end
