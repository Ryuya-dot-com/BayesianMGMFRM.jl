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
    @test !contract.automatic_promotion
    @test :reproducibility_archive in contract.stable_public_gates
    @test :external_construct_evidence in contract.external_validated_gates
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
    @test gmfrm_contract.scope === :scalar_gmfrm_guarded_experimental
    @test gmfrm_contract.minimum_dimensions == 1
    @test gmfrm_contract.maximum_dimensions == 1
    @test gmfrm_contract.discrimination == (:rater,)
    @test !gmfrm_contract.fixed_q_required
    @test mgmfrm_contract.scope ===
        :fixed_q_confirmatory_mgmfrm_guarded_experimental
    @test mgmfrm_contract.minimum_dimensions == 2
    @test mgmfrm_contract.maximum_dimensions === nothing
    @test mgmfrm_contract.discrimination == (:none,)
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

    gmfrm_design = experimental.preview(gmfrm_spec)
    mgmfrm_design = experimental.preview(mgmfrm_spec)
    @test gmfrm_design.spec === gmfrm_spec
    @test mgmfrm_design.spec === mgmfrm_spec
    @test_throws ArgumentError experimental.preview(stable_spec)
    @test_throws ArgumentError experimental.fit(
        gmfrm_spec;
        experimental = true,
    )

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
    @test_throws ArgumentError experimental.fit(
        unsupported;
        ndraws = 1,
        warmup = 0,
    )
end
