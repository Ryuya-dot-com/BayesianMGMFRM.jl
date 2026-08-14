using Test
using BayesianMGMFRM

function _experimental_namespace_data()
    rows = (
        person = ["P1", "P1", "P1", "P2", "P2", "P2"],
        rater = ["R1", "R2", "R1", "R1", "R2", "R1"],
        item = ["I1", "I1", "I2", "I1", "I2", "I2"],
        score = [0, 1, 2, 1, 0, 2],
    )
    return FacetData(
        rows;
        person = :person,
        rater = :rater,
        item = :item,
        score = :score,
    )
end

@testset "experimental namespace boundary" begin
    @test isdefined(BayesianMGMFRM, :Experimental)
    @test :Experimental ∉ names(BayesianMGMFRM)
    @test :GMFRMFit in names(BayesianMGMFRM)
    @test :MGMFRMFit in names(BayesianMGMFRM)
    experimental = BayesianMGMFRM.Experimental
    contract = experimental.surface_contract()

    @test contract.schema == "bayesianmgmfrm.experimental_surface.v1"
    @test contract.stability === :experimental
    @test contract.legacy_status === :compatibility_only
    @test contract.entrypoint == "BayesianMGMFRM.Experimental.fit(spec)"
    @test contract.legacy_entrypoint ==
        "BayesianMGMFRM.fit(spec; experimental = true)"
    @test all(name -> name ∉ names(experimental),
        (:fit, :cached_fit, :fit_cache_key, :GMFRMFit, :MGMFRMFit))
    release_scope = release_scope_summary()
    generalized_surfaces = filter(
        row -> row.family in (:gmfrm, :mgmfrm),
        release_scope.public_fit_surfaces,
    )
    @test length(generalized_surfaces) == 2
    @test all(row -> row.entrypoint == contract.entrypoint,
        generalized_surfaces)
    @test all(row -> row.legacy_entrypoint == contract.legacy_entrypoint,
        generalized_surfaces)
    gmfrm_contract = experimental.surface_contract(:gmfrm)
    mgmfrm_contract = experimental.surface_contract(:mgmfrm)
    @test gmfrm_contract.scope === :scalar_rater_consistency_gmfrm
    @test gmfrm_contract.minimum_dimensions == 1
    @test gmfrm_contract.maximum_dimensions == 1
    @test gmfrm_contract.discrimination == (:rater,)
    @test gmfrm_contract.discrimination_structure ===
        :item_discrimination_times_rater_consistency
    @test gmfrm_contract.step_sharing ===
        :rater_specific_shared_across_items_and_persons
    @test gmfrm_contract.step_constraint ===
        :first_step_zero_remaining_steps_sum_to_zero
    @test gmfrm_contract.sampler_defaults == (;
        warmup_per_chain = 100,
        retained_draws_per_chain = 100,
        chains = 2,
        total_iterations_per_chain = 200,
        warmup_fraction = 0.5,
        profile = :computational_default_not_analysis_guidance,
    )
    @test !gmfrm_contract.fixed_q_required
    @test mgmfrm_contract.scope === :fixed_q_confirmatory_mgmfrm
    @test mgmfrm_contract.minimum_dimensions == 2
    @test mgmfrm_contract.maximum_dimensions === nothing
    @test mgmfrm_contract.discrimination == (:none,)
    @test mgmfrm_contract.discrimination_structure ===
        :fixed_q_item_dimension_discrimination_with_rater_consistency
    @test mgmfrm_contract.step_sharing ===
        :item_specific_shared_across_raters_and_dimensions
    @test mgmfrm_contract.step_constraint ===
        :first_step_zero_remaining_steps_sum_to_zero
    @test mgmfrm_contract.sampler_defaults == gmfrm_contract.sampler_defaults
    @test mgmfrm_contract.fixed_q_required
    @test_throws ArgumentError experimental.surface_contract(:mfrm)
    @test experimental.GMFRMFit === BayesianMGMFRM.GMFRMFit
    @test experimental.MGMFRMFit === BayesianMGMFRM.MGMFRMFit

    data = _experimental_namespace_data()
    stable_spec = mfrm_spec(data; thresholds = :partial_credit)
    gmfrm_spec = mfrm_spec(
        data;
        family = :gmfrm,
        thresholds = :partial_credit,
        discrimination = :rater,
    )
    mgmfrm_spec = mfrm_spec(
        data;
        family = :mgmfrm,
        dimensions = 2,
        thresholds = :partial_credit,
        discrimination = :none,
        q_matrix = Bool[1 0; 0 1],
    )

    for spec in (gmfrm_spec, mgmfrm_spec)
        support = BayesianMGMFRM._guarded_generalized_spec_status(spec)
        @test support.supported
        @test support.issue === nothing
        equation = model_equation(spec)
        @test !equation.fit_ready
        @test equation.experimental_fit_available
        @test equation.experimental_fit_entrypoint ==
            "BayesianMGMFRM.Experimental.fit(spec)"
        @test equation.implementation_gap_scope ===
            :stable_compiler_and_broader_scope
        @test !isempty(equation.implementation_gaps)
    end

    gmfrm_design = experimental.preview(gmfrm_spec)
    mgmfrm_design = experimental.preview(mgmfrm_spec)
    @test gmfrm_design.spec === gmfrm_spec
    @test mgmfrm_design.spec === mgmfrm_spec
    @test_throws ArgumentError experimental.preview(stable_spec)
    @test_throws ArgumentError experimental.fit(
        gmfrm_spec;
        experimental = true,
    )

    forbidden_layout_fields = (
        :scope,
        :compiler_stage,
        :status,
        :internal,
        :public_fit,
        :experimental_public,
        :fit_ready,
    )
    stable_layout_full = fit_ready_parameter_layout(stable_spec)
    @test isequal(stable_layout_full,
        fit_ready_parameter_layout(stable_spec; view = :full))
    stable_layout_public = fit_ready_parameter_layout(stable_spec; view = :public)
    gmfrm_layout_public = fit_ready_parameter_layout(
        gmfrm_spec;
        preview = true,
        view = :public,
    )
    mgmfrm_layout_public = fit_ready_parameter_layout(
        mgmfrm_design;
        view = :public,
    )
    @test isequal(fit_ready_parameter_layout(gmfrm_spec; preview = true),
        fit_ready_parameter_layout(gmfrm_spec; preview = true, view = :full))
    @test stable_layout_public.stability === :stable
    @test stable_layout_public.fit_available
    @test stable_layout_public.entrypoint == "BayesianMGMFRM.fit(spec)"
    @test stable_layout_public.claim_scope === :minimal_mfrm_rsm_pcm
    for layout in (gmfrm_layout_public, mgmfrm_layout_public)
        @test layout.stability === :experimental
        @test layout.fit_available
        @test layout.entrypoint == contract.entrypoint
        @test all(field -> !haskey(layout, field), forbidden_layout_fields)
        @test all(row -> !haskey(row, :status), layout.transforms)
        @test all(row -> !haskey(row, :status), layout.constraints)
        @test all(row -> !haskey(row, :status) &&
            !haskey(row, :estimation_status),
            layout.identification_declarations)
    end
    @test gmfrm_layout_public.claim_scope === :scalar_rater_consistency_only
    @test mgmfrm_layout_public.claim_scope === :fixed_q_confirmatory_only
    @test gmfrm_layout_public.raw_parameter_names ==
        fit_ready_parameter_layout(gmfrm_spec; preview = true).raw_parameter_names
    @test mgmfrm_layout_public.constrained_parameter_names ==
        fit_ready_parameter_layout(mgmfrm_design).constrained_parameter_names

    stable_domain_full = domain_compilation_summary(stable_spec)
    @test isequal(stable_domain_full,
        domain_compilation_summary(stable_spec; view = :full))
    stable_domain_public = domain_compilation_summary(stable_spec; view = :public)
    gmfrm_domain_public = domain_compilation_summary(
        gmfrm_design;
        view = :public,
    )
    mgmfrm_domain_public = domain_compilation_summary(
        mgmfrm_spec;
        preview = true,
        view = :public,
    )
    @test isequal(domain_compilation_summary(gmfrm_spec; preview = true),
        domain_compilation_summary(gmfrm_spec; preview = true, view = :full))
    @test all(row -> row.stability === :stable && row.fit_available &&
        row.entrypoint == "BayesianMGMFRM.fit(spec)", stable_domain_public)
    for rows in (gmfrm_domain_public, mgmfrm_domain_public)
        @test all(row -> row.stability === :experimental &&
            row.fit_available && row.entrypoint == contract.entrypoint, rows)
        @test all(row -> all(field -> !haskey(row, field),
            forbidden_layout_fields), rows)
    end
    @test any(row -> row.raw_block === :log_item_discrimination_free &&
        row.constrained_block === :item_discrimination,
        gmfrm_domain_public)
    @test any(row -> row.compiled_role === :loading_mask &&
        row.loading_mask == Bool[1 0; 0 1], mgmfrm_domain_public)

    private_anchor_path = "/Users/example/private-anchor.json"
    anchored_spec = mfrm_spec(
        data;
        thresholds = :partial_credit,
        anchors = [(;
            block = :rater,
            level = "R2",
            value = 0.25,
            type = :hard,
            source = :facets,
            source_hash = repeat("0123456789abcdef", 4),
            repository_path = private_anchor_path,
            source_path = "/Users/example/private-source.json",
            file_path = "/Users/example/private-file.json",
        )],
    )
    public_anchor_domain = domain_compilation_summary(
        anchored_spec;
        preview = true,
        view = :public,
    )
    anchor_row = only(filter(row -> row.domain_option === :anchors,
        public_anchor_domain))
    @test anchor_row.option_value.source === :facets
    @test haskey(anchor_row.option_value, :source_hash)
    @test !haskey(anchor_row.option_value, :repository_path)
    @test !haskey(anchor_row.option_value, :source_path)
    @test !haskey(anchor_row.option_value, :file_path)
    @test !occursin(private_anchor_path, sprint(show, public_anchor_domain))

    @test isequal(model_ladder(), model_ladder(view = :full))
    public_ladder = model_ladder(view = :public)
    @test count(row -> row.stability === :experimental && row.fit_available,
        public_ladder) == 2
    @test all(row -> all(field -> !haskey(row, field),
        (:scope, :estimation_status, :public_fit, :experimental_public)),
        public_ladder)
    public_linking = anchor_linking_summary(anchored_spec; view = :public)
    @test public_linking.schema ==
        "bayesianmgmfrm.anchor_linking_summary_public.v1"
    @test !haskey(public_linking, :estimation_status)
    @test !haskey(public_linking, :next_gate)
    @test !haskey(public_linking, :anchor_sensitivity_summary)
    public_rating_audit = rating_design_audit(anchored_spec; view = :public)
    @test public_rating_audit.schema ==
        "bayesianmgmfrm.rating_design_audit_public.v1"
    @test !haskey(public_rating_audit, :estimation_status)
    @test public_rating_audit.anchor_linking.schema ==
        "bayesianmgmfrm.anchor_linking_summary_public.v1"
    @test !occursin(private_anchor_path, sprint(show, public_rating_audit))
    public_rating_check = rating_design_check(anchored_spec; view = :public)
    @test public_rating_check.schema ==
        "bayesianmgmfrm.rating_design_check_public.v1"
    @test public_rating_check.object === :rating_design_check
    @test all(row -> haskey(row, :check) && !haskey(row, :audit),
        public_rating_check.rows)
    @test public_rating_check.summary == public_rating_audit.summary
    @test !occursin("audit", lowercase(sprint(show, public_rating_check)))
    @test model_surface_check(stable_spec; view = :public) ==
        model_surface_audit(stable_spec; view = :public)
    full_surface_check = model_surface_check(stable_spec)
    @test all(row -> row.schema ==
        "bayesianmgmfrm.model_surface_check_row.v1",
        full_surface_check)
    @test !occursin("audit", lowercase(sprint(show, full_surface_check)))
    @test model_manifest(anchored_spec; view = :public).rating_design.schema ==
        "bayesianmgmfrm.rating_design_audit_public.v1"

    @test isequal(related_software_capability_matrix(),
        related_software_capability_matrix(view = :full))
    public_software = related_software_capability_matrix(view = :public)
    @test public_software.stability === :stable
    @test all(source -> !startswith(source.url, "local://"),
        public_software.sources)
    @test all(row -> all(url -> !startswith(url, "local://"),
        row.source_urls), public_software.rows)
    @test all(row -> !haskey(row, :comparison_gate) &&
        !haskey(row, :v0_1_1_position), public_software.rows)

    @test_throws ArgumentError fit_ready_parameter_layout(stable_spec; view = :bad)
    @test_throws ArgumentError domain_compilation_summary(stable_spec; view = :bad)
    @test_throws ArgumentError model_ladder(view = :bad)
    @test_throws ArgumentError anchor_linking_summary(stable_spec; view = :bad)
    @test_throws ArgumentError rating_design_audit(stable_spec; view = :bad)
    @test_throws ArgumentError rating_design_check(stable_spec; view = :bad)
    @test_throws ArgumentError related_software_capability_matrix(view = :bad)

    gmfrm_candidate =
        model_manifest(gmfrm_design).design.raw_parameterization.promotion_candidate
    gmfrm_decision = gmfrm_candidate.experimental_public_api
    mgmfrm_candidate =
        model_manifest(mgmfrm_design).design.raw_parameterization.confirmatory_candidate
    mgmfrm_decision = mgmfrm_candidate.experimental_public_api_decision
    for decision in (gmfrm_decision, mgmfrm_decision)
        @test decision.proposed_entrypoint == contract.entrypoint
        @test decision.legacy_entrypoint == contract.legacy_entrypoint
        @test decision.summary.canonical_namespace_enabled
        @test decision.summary.experimental_keyword_enabled
        @test decision.summary.legacy_keyword_status === :compatibility_only
        @test any(row -> row.option === :entrypoint &&
            row.value == contract.entrypoint,
            decision.accepted_candidate_options)
        @test any(row -> row.option === :legacy_entrypoint &&
            row.value == contract.legacy_entrypoint &&
            row.status === :compatibility_only,
            decision.accepted_candidate_options)
    end

    smoke_controls = (
        backend = :advancedhmc,
        ndraws = 1,
        warmup = 0,
        chains = 1,
        seed = 20260722,
        step_size = 0.02,
        max_depth = 1,
        metric = :unit,
    )
    cache_controls = (
        ndraws = 2,
        warmup = 0,
        chains = 1,
        seed = 20260723,
        step_size = 0.02,
        max_depth = 1,
        metric = :unit,
    )
    namespaced_key = experimental.fit_cache_key(gmfrm_spec; cache_controls...)
    legacy_key = fit_cache_key(
        gmfrm_spec;
        experimental = true,
        backend = :advancedhmc,
        cache_controls...,
    )
    @test namespaced_key == legacy_key

    run_fit_smoke = abspath(PROGRAM_FILE) == abspath(@__FILE__) ||
        lowercase(get(ENV,
            "BAYESIANMGMFRM_EXPERIMENTAL_BOUNDARY_SMOKE", "false")) in
            ("1", "true", "yes")
    if run_fit_smoke
        gmfrm_fit = experimental.fit(gmfrm_spec; smoke_controls...)
        @test gmfrm_fit isa experimental.GMFRMFit
        @test fit_metadata(gmfrm_fit).experimental_public

        namespaced_fit = experimental.fit(
            mgmfrm_spec;
            smoke_controls...,
        )
        @test namespaced_fit isa experimental.MGMFRMFit
        @test fit_metadata(namespaced_fit).experimental_public
        mgmfrm_artifact = fit_artifact(
            namespaced_fit;
            include_environment = false,
        )
        @test mgmfrm_artifact.entrypoint == contract.entrypoint
        @test mgmfrm_artifact.legacy_entrypoint == contract.legacy_entrypoint

        mktempdir() do cache_dir
            cache_path = joinpath(cache_dir, "gmfrm.jls")
            cache_record = experimental.cached_fit(
                gmfrm_spec;
                cache_path,
                return_record = true,
                cache_controls...,
            )
            @test cache_record.object === :fit_cache
            @test cache_record.fit isa experimental.GMFRMFit
            @test cache_record.artifact.entrypoint == contract.entrypoint
            @test cache_record.artifact.legacy_entrypoint ==
                contract.legacy_entrypoint
            @test isfile(cache_path)

            cache_hit = experimental.cached_fit(
                gmfrm_spec;
                cache_path,
                cache_controls...,
            )
            @test cache_hit.draws == cache_record.fit.draws
        end
    end

    unsupported = mfrm_spec(
        data;
        family = :gmfrm,
        thresholds = :rating_scale,
        discrimination = :rater,
    )
    unsupported_status =
        BayesianMGMFRM._guarded_generalized_spec_status(unsupported)
    @test !unsupported_status.supported
    @test unsupported_status.issue isa
        BayesianMGMFRM._GuardedGeneralizedSupportIssue
    @test unsupported_status.issue.option === :thresholds
    @test unsupported_status.issue.value === :rating_scale
    @test unsupported_status.issue.next_gate ===
        :guarded_generalized_threshold_contract
    @test !model_equation(unsupported).experimental_fit_available
    @test_throws ArgumentError experimental.fit(
        unsupported;
        ndraws = 1,
        warmup = 0,
    )
end
