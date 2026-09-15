# Reuse the caller's sampled or restored result; this check never fits a model.
function check_fixed_q_report_bundle(result, directory)
    path = joinpath(directory, "fixed-q-figures")
    if Base.get_extension(B, :BayesianMGMFRMCairoMakieExt) === nothing
        @test_throws ArgumentError B._save_mfrm_fixed_q_report_bundle(path, result)
        @test !ispath(path)
        return
    end
    json(path) = B.JSON3.read(read(path, String), Dict{String,Any})
    files(path) = Dict(relpath(joinpath(dir, name), path) => read(joinpath(dir, name))
        for (dir, _, names) in walkdir(path) for name in names)
    coordinates = result.model_coordinates
    person = first(row.parameter for row in coordinates if row.block === :person && row.dimension == 2)
    derived = first(row.parameter for row in coordinates if row.derived)
    fixed = first(row.parameter for row in coordinates if row.block === :item_steps && row.fixed)
    selection = (; parameters = [person, derived, fixed])
    figures = (; posterior = selection, diagnostics = selection, predictive = (;))
    indices = [size(result.record.run.draws, 1), 1, size(result.record.run.draws, 1), 2]
    options = (; posterior_interval = 0.8, predictive_interval = 0.8, draw_indices = indices, seed = 42)
    before = deepcopy(result.record)
    Random.seed!(918); next_random = rand(); Random.seed!(918)
    manifest = B._save_mfrm_fixed_q_report_bundle(path, result; figures, options...,
        max_rows = 0, require_complete = true)
    @test rand() == next_random
    @test isequal(result.record.run, before.run)
    @test result.record.content_hash == before.content_hash
    @test manifest.schema == "bayesianmgmfrm.fit_report_bundle_export.v2"
    report = load_fit_report_bundle(path; require_complete = true)
    @test report["family"] == "mfrm_fixed_q"
    @test report["report_status"] == "complete"
    @test report["metadata"]["source_sample_content_hash"] == result.record.content_hash
    for entry in manifest.figures
        payload = json(joinpath(path, "figures", "$(entry.kind).json"))
        @test payload["report_content_hash"]["value"] == manifest.report_content_hash.value
        for key in ("backend", "scale_convention", "target_identity", "source_sample_schema", "source_sample_content_hash")
            @test payload[key] == report["metadata"][key]
        end
        @test occursin(entry.caption, read(joinpath(path, "fit_report.md"), String))
        @test occursin("MCMC", entry.caption)
        for file in entry.files
            @test bytes2hex(B.sha256(read(joinpath(path, file.path)))) == file.content_hash.value
        end
    end
    posterior = json(joinpath(path, "figures/posterior.json"))["data"]
    @test posterior["interval"] == 0.8
    @test [row["parameter"] for row in posterior["rows"]] == selection.parameters
    for row in posterior["rows"]
        source = only(filter(r -> r["parameter"] == row["parameter"], report["direct_posterior"]["rows"]))
        for key in ("median", "lower", "upper", "fixed", "derived", "dimension")
            @test row[key] == source[key]
        end
    end
    diagnostic = json(joinpath(path, "figures/diagnostics.json"))["data"]
    @test diagnostic["chain_ids"] == result.record.run.chain_ids
    @test diagnostic["iterations"] == result.record.run.iterations
    @test !haskey(diagnostic, "summary")
    @test diagnostic["diagnostic"] == posterior["diagnostic"]
    @test only(filter(r -> r["fixed"], diagnostic["rows"]))["ranks"] === nothing
    predictive = json(joinpath(path, "figures/predictive.json"))["data"]
    @test predictive == B._json_export_value(B._mfrm_fixed_q_predictive_plot_data(result;
        interval = 0.8, draw_indices = indices, seed = 42))
    for key in ("draw_indices", "chain_ids", "iterations", "selection", "n_replicates", "n_unique_draws", "n_retained", "n_observations", "rng")
        @test predictive[key] == report["posterior_predictive"][key]
    end
    @test predictive["diagnostic"] == posterior["diagnostic"]
    source = filter(r -> r["statistic"] == "category_proportion", report["posterior_predictive"]["rows"])
    for (row, reference) in zip(predictive["rows"], source), key in ("observed", "replicated_mean", "replicated_lower", "replicated_upper")
        @test row[key] == reference[key]
    end
    # Failure after the first figure was rendered must preserve every destination byte.
    write(joinpath(path, "user-note.txt"), "Keep this unrelated file.")
    original = files(path)
    @test_throws ArgumentError B._save_mfrm_fixed_q_report_bundle(path, result; overwrite = true,
        figures = (; posterior = selection, diagnostics = (; parameters = ["absent"])))
    @test files(path) == original
    for extra in ((; figures = (wright = (;),)), (; seed = true),
            (; figures = (predictive = (;),), include_posterior_predictive = false),
            (; figures = (predictive = (;),), ndraws = 0, require_complete = true))
        @test_throws ArgumentError B._save_mfrm_fixed_q_report_bundle(path, result; overwrite = true, extra...)
        @test files(path) == original
    end
    for ext in ("pdf", "svg", "json")
        file = joinpath(path, "figures/posterior.$ext")
        bytes = read(file); write(file, vcat(bytes, UInt8[0x20]))
        @test_throws ArgumentError load_fit_report_bundle(path)
        write(file, bytes)
    end
    replay = joinpath(directory, "fixed-q-predictive-replay")
    loaded = B._restore_mfrm_fixed_q_samples(result.record; expected_identity = result.record.target_identity)
    B._save_mfrm_fixed_q_report_bundle(replay, loaded; figures = (predictive = (;),), options...)
    @test json(joinpath(replay, "figures/predictive.json"))["data"] == predictive
    @test load_fit_report_bundle(path)["metadata"] == report["metadata"]
end
