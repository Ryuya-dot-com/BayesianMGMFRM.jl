module RefitMetadataChecks
using Test, BayesianMGMFRM
const B = BayesianMGMFRM

function panel(; metadata = true)
    rows = [(person = "P$p", rater = "R$r", item = "I$i",
        score = mod(p + r + i + event, 3), event = "E$event",
        response = "P$p-R$r-E$event", rowid = "P$p-R$r-I$i-E$event")
        for event in 1:3 for p in 1:3 for r in 1:2 for i in 1:4]
    table = (; (k => getproperty.(rows, k) for k in keys(first(rows)))...)
    options = metadata ? (; occasion = :event, response_id = :response, form = :rowid) : (;)
    return FacetData(table; person = :person, rater = :rater,
        item = :item, score = :score, options...)
end

@testset "Refits preserve heldout metadata without fitting its levels" begin
    data = panel()
    plain = panel(; metadata = false)
    plan = kfold_plan(data; k = 3, group_by = :occasion)
    # The general audit still reports unseen metadata; current refit likelihoods
    # use person/rater/item/category maps only.
    audit = kfold_plan_diagnostics(data, plan)
    @test !audit.passed
    @test all(row -> row.facet in (:occasion, :response_id, :form),
        filter(row -> row.refit_blocker, audit.rows))
    @test B._check_kfold_refit_plan_for_execution(data, plan).passed
    @test B._check_loo_refit_plan_for_execution(data,
        loo_refit_plan(data; observations = [1])).passed

    for fold in plan.fold_rows
        training = B._loo_refit_training_data(data, fold.training_observations)
        scored = B._loo_refit_score_data(data, training, fold.heldout_observations)
        @test isempty(intersect(training.optional_levels[:occasion],
            [data.optional_levels[:occasion][data.optional[:occasion][i]]
                for i in fold.heldout_observations]))
        @test facet_response_table(scored) ==
            facet_response_table(data; observations = fold.heldout_observations)
        @test training.n + scored.n == data.n
        @test length(training.optional_levels[:occasion]) == 2
    end

    # Tiny real refits test the full data -> fit -> heldout scoring path. They
    # are software checks, not qualified inference or calibration evidence.
    options = (; ndraws = 2, warmup = 1, chains = 1,
        step_size = 0.02, seed = 92401, return_fits = true)
    for family in (:mfrm, :gmfrm, :mgmfrm)
        spec_options = family === :mgmfrm ?
            (; family, dimensions = 2, q_matrix = Bool[1 0; 1 0; 0 1; 0 1]) :
            family === :gmfrm ? (; family, discrimination = :rater) : (; family)
        fit_options = family === :mfrm ? (; backend = :julia) :
            (; backend = :advancedhmc, experimental = true, max_depth = 1,
                metric = :unit)
        coordinates = family === :mgmfrm ?
            (; sampling_coordinates = :orthogonal_person_mean_item_offset) : (;)
        with_metadata = kfold_refit(mfrm_spec(data; spec_options...), plan;
            options..., fit_options..., coordinates...)
        without_metadata = kfold_refit(mfrm_spec(plain; spec_options...), plan;
            options..., fit_options..., coordinates...)
        @test with_metadata.plan_diagnostics.passed
        @test with_metadata.n_observations == data.n
        @test with_metadata.fold_logliks == without_metadata.fold_logliks
        @test all(isfinite, reduce(vcat, vec.(with_metadata.fold_logliks)))
        @test all(a.draws == b.draws for (a, b) in
            zip(with_metadata.fold_fits, without_metadata.fold_fits))
        if family === :mgmfrm
            @test all(f.sampler_controls.sampling_coordinates ===
                :orthogonal_person_mean_item_offset for f in with_metadata.fold_fits)
        end
        loo = loo_refit(mfrm_spec(data; spec_options...),
            loo_refit_plan(data; observations = [1]);
            options..., fit_options..., coordinates...)
        @test loo.plan_diagnostics.passed
        @test all(isfinite, only(loo.fold_logliks))
    end

    # An unseen fitted person/rater/item still requires a different predictive
    # target; metadata support must not silently implement new-level prediction.
    for facet in (:person, :rater, :item)
        blocked = kfold_plan(data; k = 2, group_by = facet)
        @test_throws ArgumentError B._check_kfold_refit_plan_for_execution(data, blocked)
        fold = first(blocked.fold_rows)
        training = B._loo_refit_training_data(data, fold.training_observations)
        @test_throws ArgumentError B._loo_refit_score_data(data, training,
            fold.heldout_observations)
    end
end
end
