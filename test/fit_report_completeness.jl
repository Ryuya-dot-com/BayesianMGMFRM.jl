using BayesianMGMFRM
using Random
using Test

function _synthetic_fit_report(; loo_error::Bool, record_health::Bool = true)
    loo = loo_error ? (;
        status = :error,
        exception = :ArgumentError,
        message = "synthetic LOO failure",
    ) : (;
        status = :not_requested,
    )
    report = (;
        schema = "bayesianmgmfrm.fit_report.v1",
        object = :fit_report,
        created_at = "2026-08-14T00:00:00",
        family = :mfrm,
        thresholds = :partial_credit,
        dimensions = 1,
        dimension_labels = ["ability"],
        estimation_status = :fit_supported,
        status_policy = (; status_label = :fit_supported),
        posterior = (;
            status = :computed,
            rows = [(; parameter = "person[P1]", mean = 0.0)],
            n_rows = 1,
        ),
        loo,
        artifact = (; status = :not_requested),
    )
    record_health || return report
    health = fit_report_health(report)
    return merge(report, (;
        report_status = health.status,
        report_health = health,
    ))
end

@testset "fit report completeness contract" begin
    legacy_complete = _synthetic_fit_report(;
        loo_error = false,
        record_health = false,
    )
    legacy_health = fit_report_health(legacy_complete)
    @test legacy_health.status === :complete
    @test legacy_health.complete
    @test legacy_health.n_sections == 3
    @test legacy_health.n_computed_sections == 1
    @test legacy_health.n_not_requested_sections == 2
    @test legacy_health.n_error_sections == 0
    @test isempty(legacy_health.error_sections)

    complete_report = _synthetic_fit_report(loo_error = false)
    complete_health = fit_report_health(complete_report)
    @test complete_report.report_status === :complete
    @test complete_health.complete
    @test complete_health == complete_report.report_health

    incomplete_report = _synthetic_fit_report(loo_error = true)
    incomplete_health = fit_report_health(incomplete_report)
    @test incomplete_report.report_status === :incomplete
    @test incomplete_health.status === :incomplete
    @test !incomplete_health.complete
    @test incomplete_health.n_error_sections == 1
    @test only(incomplete_health.error_sections).section === :loo
    @test only(incomplete_health.error_sections).exception === :ArgumentError
    @test only(incomplete_health.error_sections).message ==
        "synthetic LOO failure"

    inconsistent_status = merge(incomplete_report, (;
        report_status = :complete,
    ))
    @test_throws ArgumentError fit_report_health(inconsistent_status)
    inconsistent_health = merge(incomplete_report, (;
        report_health = merge(incomplete_report.report_health, (;
            n_error_sections = 0,
        )),
    ))
    @test_throws ArgumentError fit_report_health(inconsistent_health)

    public_incomplete = fit_report_public(incomplete_report)
    @test public_incomplete.status === :supported
    @test public_incomplete.report_status === :incomplete
    @test public_incomplete.report_health.status === :incomplete
    @test public_incomplete.report_health.n_error_sections == 1
    @test fit_report_health(public_incomplete).status === :incomplete
    @test fit_report_public(public_incomplete) === public_incomplete

    complete_dossier = fit_report_dossier(
        :complete => complete_report;
        require_complete = true,
    )
    @test complete_dossier.report_status === :complete
    @test complete_dossier.complete
    @test complete_dossier.n_incomplete_reports == 0
    @test complete_dossier.n_error_sections == 0

    dossier = fit_report_dossier(
        :complete => complete_report,
        :incomplete => incomplete_report;
        include_reports = true,
    )
    @test dossier.report_status === :incomplete
    @test !dossier.complete
    @test dossier.n_incomplete_reports == 1
    @test dossier.n_error_sections == 1
    incomplete_row = only(row for row in dossier.report_rows
        if row.model == "incomplete")
    @test incomplete_row.report_status === :incomplete
    @test !incomplete_row.report_complete
    @test incomplete_row.n_error_sections == 1
    inconsistent_dossier = merge(dossier, (; n_error_sections = 0))
    @test_throws ArgumentError fit_report_dossier_markdown(
        inconsistent_dossier,
    )
    @test_throws ArgumentError fit_report_dossier(
        :incomplete => incomplete_report;
        require_complete = true,
    )

    mktempdir() do directory
        inconsistent_path = joinpath(directory, "inconsistent.json")
        @test_throws ArgumentError save_fit_report(
            inconsistent_path,
            inconsistent_status,
        )
        @test !ispath(inconsistent_path)

        report_path = joinpath(directory, "incomplete.json")
        save_fit_report(report_path, incomplete_report)
        loaded = load_fit_report(report_path)
        @test loaded["report_status"] == "incomplete"
        @test fit_report_health(loaded).status === :incomplete
        @test_throws ArgumentError load_fit_report(report_path;
            require_complete = true)

        rejected_report_path = joinpath(directory, "rejected.json")
        @test_throws ArgumentError save_fit_report(
            rejected_report_path,
            incomplete_report;
            require_complete = true,
        )
        @test !ispath(rejected_report_path)

        rejected_tables = joinpath(directory, "rejected_tables")
        @test_throws ArgumentError save_fit_report_tables(
            rejected_tables,
            incomplete_report;
            require_complete = true,
        )
        @test !ispath(rejected_tables)

        rejected_markdown = joinpath(directory, "rejected.md")
        @test_throws ArgumentError save_fit_report_markdown(
            rejected_markdown,
            incomplete_report;
            require_complete = true,
        )
        @test !ispath(rejected_markdown)

        rejected_bundle = joinpath(directory, "rejected_bundle")
        @test_throws ArgumentError save_fit_report_bundle(
            rejected_bundle,
            incomplete_report;
            require_complete = true,
        )
        @test !ispath(rejected_bundle)

        incomplete_bundle = joinpath(directory, "incomplete_bundle")
        save_fit_report_bundle(incomplete_bundle, incomplete_report)
        @test load_fit_report_bundle(incomplete_bundle)["report_status"] ==
            "incomplete"
        @test_throws ArgumentError load_fit_report_bundle(
            incomplete_bundle;
            require_complete = true,
        )
        @test_throws ArgumentError load_fit_report_bundle(
            incomplete_bundle;
            return_manifest = true,
            require_complete = true,
        )

        dossier_path = joinpath(directory, "dossier.json")
        save_fit_report_dossier(dossier_path, dossier)
        loaded_dossier = load_fit_report_dossier(dossier_path)
        @test loaded_dossier["report_status"] == "incomplete"
        @test !loaded_dossier["complete"]
        @test loaded_dossier["n_incomplete_reports"] == 1
        @test loaded_dossier["n_error_sections"] == 1
        @test_throws ArgumentError load_fit_report_dossier(dossier_path;
            require_complete = true)

        rejected_dossier_path = joinpath(directory, "rejected_dossier.json")
        @test_throws ArgumentError save_fit_report_dossier(
            rejected_dossier_path,
            dossier;
            require_complete = true,
        )
        @test !ispath(rejected_dossier_path)

        rejected_dossier_markdown = joinpath(
            directory,
            "rejected_dossier.md",
        )
        @test_throws ArgumentError save_fit_report_dossier_markdown(
            rejected_dossier_markdown,
            dossier;
            require_complete = true,
        )
        @test !ispath(rejected_dossier_markdown)
    end

    tiny_table = (;
        examinee = ["E1", "E1", "E2", "E2", "E3", "E3"],
        rater = ["R1", "R2", "R1", "R2", "R1", "R2"],
        item = ["I1", "I2", "I1", "I2", "I2", "I1"],
        score = [0, 1, 1, 2, 2, 0],
    )
    tiny_data = FacetData(
        tiny_table;
        person = :examinee,
        rater = :rater,
        item = :item,
        score = :score,
    )
    tiny_spec = mfrm_spec(tiny_data; thresholds = :partial_credit)
    tiny_fit = fit(
        tiny_spec;
        backend = :julia,
        ndraws = 2,
        warmup = 0,
        chains = 1,
        step_size = 0.03,
        init = initial_params(tiny_spec),
        rng = MersenneTwister(20260814),
    )
    actual_incomplete = fit_report(
        tiny_fit;
        include_posterior_predictive = false,
        include_calibration = false,
        include_waic = false,
        artifact_include_environment = false,
    )
    @test actual_incomplete.loo.status === :error
    @test actual_incomplete.report_status === :incomplete
    @test actual_incomplete.report_health.n_error_sections == 1
    @test_throws ArgumentError fit_report(
        tiny_fit;
        include_posterior_predictive = false,
        include_calibration = false,
        include_waic = false,
        artifact_include_environment = false,
        require_complete = true,
    )
    actual_complete = fit_report(
        tiny_fit;
        include_posterior_predictive = false,
        include_calibration = false,
        include_waic = false,
        include_loo = false,
        artifact_include_environment = false,
        require_complete = true,
    )
    @test actual_complete.report_status === :complete
    @test actual_complete.report_health.complete
end
