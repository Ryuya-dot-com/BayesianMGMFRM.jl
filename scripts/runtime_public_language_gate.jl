#!/usr/bin/env julia

using BayesianMGMFRM
using JSON3
using Random

include(joinpath(@__DIR__, "public_language_gate.jl"))
using .PublicLanguageGate

const ROOT = abspath(normpath(joinpath(@__DIR__, "..")))

# Three names were exported by v0.1.0 and two more are present on origin/main.
# Keep the v0.1.x namespace compatible, but treat their maintainer-oriented
# docstrings as outside the reader-facing runtime surface scanned here.
const LEGACY_MAINTENANCE_EXPORTS = Set((
    :case_study_provenance_manifest,
    :evidence_artifact_schema_policy,
    :evidence_metadata,
    :release_gate_check,
    :release_scope_summary,
))

const EXPERIMENTAL_PUBLIC_DOCSTRINGS = (
    :GMFRMFit,
    :MGMFRMFit,
    :cached_fit,
    :fit,
    :fit_cache_key,
    :preview,
    :surface_contract,
)

function exported_docstring_outputs()
    outputs = Pair{String,String}[]
    for name in sort!(collect(names(BayesianMGMFRM;
            all = false, imported = false)); by = String)
        name in LEGACY_MAINTENANCE_EXPORTS && continue
        binding = Docs.Binding(BayesianMGMFRM, name)
        doc = Docs.doc(binding)
        doc === nothing && continue
        text = sprint(show, MIME"text/plain"(), doc)
        push!(outputs, "docstring:$(String(name))" => text)
    end
    module_binding = Docs.Binding(BayesianMGMFRM, :Experimental)
    module_doc = Docs.doc(module_binding)
    module_doc === nothing || push!(outputs,
        "docstring:Experimental" =>
            sprint(show, MIME"text/plain"(), module_doc))
    for name in EXPERIMENTAL_PUBLIC_DOCSTRINGS
        binding = Docs.Binding(BayesianMGMFRM.Experimental, name)
        doc = Docs.doc(binding)
        doc === nothing && error(
            "missing public Experimental docstring for $(String(name))")
        text = sprint(show, MIME"text/plain"(), doc)
        push!(outputs, "docstring:Experimental.$(String(name))" => text)
    end
    return outputs
end

function representative_objects()
    ratings = (;
        examinee = ["E1", "E1", "E1", "E1", "E2", "E2", "E2", "E2"],
        rater = ["R1", "R2", "R1", "R2", "R1", "R2", "R1", "R2"],
        item = ["I1", "I1", "I2", "I2", "I1", "I1", "I2", "I2"],
        score = [0, 1, 2, 0, 1, 2, 0, 2],
    )
    data = FacetData(ratings;
        person = :examinee,
        rater = :rater,
        item = :item,
        score = :score,
    )
    clustered_ratings = merge(ratings, (;
        response_id = ["S1", "S1", "S1", "S1", "S2", "S2", "S2", "S2"],
        testlet_id = fill("T1", 8),
    ))
    clustered_data = FacetData(clustered_ratings;
        person = :examinee,
        rater = :rater,
        item = :item,
        score = :score,
        response_id = :response_id,
        testlet_id = :testlet_id,
    )
    validation = validate_design(data)
    spec = mfrm_spec(data; thresholds = :partial_credit,
        validation_report = validation)
    design = getdesign(spec)
    clustered_spec = mfrm_spec(clustered_data; thresholds = :partial_credit)
    clustered_design = getdesign(clustered_spec)
    mgmfrm_spec = mfrm_spec(data;
        thresholds = :partial_credit,
        family = :mgmfrm,
        dimensions = 2,
        q_matrix = Bool[1 0; 0 1],
    )
    preview = getdesign(mgmfrm_spec; preview = true)
    n_parameters = length(design.parameter_names)
    prior = MFRMPrior()
    mfrm_fit = MFRMFit(
        design,
        prior,
        zeros(1, n_parameters),
        [0.0],
        1.0,
        [1],
        [1],
        [1.0],
        :julia,
        :random_walk_metropolis,
        0,
        0.1,
    )
    clustered_fit = MFRMFit(
        clustered_design,
        prior,
        zeros(1, length(clustered_design.parameter_names)),
        [0.0],
        1.0,
        [1],
        [1],
        [1.0],
        :julia,
        :random_walk_metropolis,
        0,
        0.1,
    )
    generalized_args = (
        design,
        BayesianMGMFRM._SourceFixturePrior(),
        zeros(1, n_parameters),
        [0.0],
        zeros(1, n_parameters),
        [0.0],
        zeros(1, data.n),
        [1],
        [1],
        [1.0],
        :advancedhmc,
        :nuts,
        0,
        0.1,
        NamedTuple[],
        NamedTuple(),
        NamedTuple(),
    )
    local_dependence_grid = local_dependence_simulation_grid(;
        repetitions = 1,
        base_seed = 20260720,
        n_persons = 8,
        n_testlets = 4,
        items_per_testlet = 2,
        n_raters = 2,
        n_categories = 3,
    )
    local_dependence_known_truth = simulate_local_dependence(
        first(local_dependence_grid);
        max_ratings = 10_000,
        max_probability_cells = 50_000,
    )
    local_dependence_calibration = local_dependence_calibration_contract()
    local_dependence_calibration_result = local_dependence_calibration_row(
        first(local_dependence_grid);
        contract = local_dependence_calibration,
        status = :generation_failed,
        failure_code = :representative_run_not_executed,
    )
    local_dependence_calibration_overview =
        local_dependence_calibration_summary(
            [first(local_dependence_grid)],
            [local_dependence_calibration_result];
            contract = local_dependence_calibration,
        )
    local_dependence_pilot_grid = local_dependence_simulation_grid(;
        repetitions = 30,
        base_seed = 20260720,
        phase = :pilot,
        grid_id = "runtime_public_language_ld1b1",
        n_persons = 40,
        n_testlets = 4,
        items_per_testlet = 3,
        n_raters = 4,
        n_categories = 4,
    )
    local_dependence_pilot_contract =
        local_dependence_calibration_pilot_contract()
    local_dependence_pilot_preflight =
        local_dependence_calibration_pilot_preflight(
            local_dependence_pilot_grid;
            contract = local_dependence_pilot_contract,
        )
    return (;
        data,
        validation,
        spec,
        design,
        mgmfrm_spec,
        preview,
        issue = isempty(validation.issues) ?
            ValidationIssue(:small_example, :warning,
                "The representative design is intentionally small.") :
            first(validation.issues),
        prior,
        target = MFRMLogDensity(design),
        mfrm_fit,
        gmfrm_fit = GMFRMFit(generalized_args...),
        mgmfrm_fit = MGMFRMFit(generalized_args...),
        clustered_data,
        testlet_audit = testlet_design_audit(clustered_data),
        local_dependence = local_dependence_contract(),
        local_dependence_summary = local_dependence_summary(
            clustered_fit;
            draw_indices = [1],
            rng = MersenneTwister(20260720),
        ),
        local_dependence_grid,
        local_dependence_known_truth,
        local_dependence_calibration,
        local_dependence_calibration_result,
        local_dependence_calibration_overview,
        local_dependence_pilot_contract,
        local_dependence_pilot_preflight,
        standardized_residuals = predictive_standardized_residuals(
            design,
            zeros(1, n_parameters),
        ),
    )
end

function show_outputs(objects)
    values = (
        "FacetData" => objects.data,
        "ValidationIssue" => objects.issue,
        "ValidationReport" => objects.validation,
        "FacetSpec:MFRM" => objects.spec,
        "FacetDesign:MFRM" => objects.design,
        "FacetSpec:MGMFRM" => objects.mgmfrm_spec,
        "FacetDesign:MGMFRM" => objects.preview,
        "MFRMPrior" => objects.prior,
        "MFRMLogDensity" => objects.target,
        "MFRMFit" => objects.mfrm_fit,
        "GMFRMFit" => objects.gmfrm_fit,
        "MGMFRMFit" => objects.mgmfrm_fit,
    )
    outputs = Pair{String,String}[]
    for (label, value) in values
        push!(outputs, "show:$label" => sprint(show, value))
        push!(outputs, "show:text/plain:$label" =>
            sprint(show, MIME"text/plain"(), value))
    end
    return outputs
end

function clustered_diagnostic_outputs(objects)
    values = (
        "testlet-design-audit" => objects.testlet_audit,
        "local-dependence-contract" => objects.local_dependence,
        "local-dependence-summary" => objects.local_dependence_summary,
        "predictive-standardized-residuals" => objects.standardized_residuals,
    )
    outputs = Pair{String,String}[]
    for (label, value) in values
        push!(outputs, "clustered:$label:json" => JSON3.write(value))
        push!(outputs, "clustered:$label:show" => sprint(show, value))
    end
    return outputs
end

function runtime_dynamic_projection(value)
    Base.@nospecialize value
    if value === nothing || ismissing(value) || value isa Bool ||
            value isa Number || value isa Symbol || value isa AbstractString
        return value
    elseif value isa NamedTuple || value isa AbstractDict
        output = Dict{String,Any}()
        for (key, element) in pairs(value)
            output[string(key)] = runtime_dynamic_projection(element)
        end
        return output
    elseif value isa AbstractArray || value isa Tuple || value isa AbstractSet
        return Any[runtime_dynamic_projection(element) for element in value]
    elseif value isa Pair
        return Any[
            runtime_dynamic_projection(first(value)),
            runtime_dynamic_projection(last(value)),
        ]
    end
    names = propertynames(value)
    isempty(names) && return sprint(show, value)
    output = Dict{String,Any}()
    for name in names
        output[String(name)] = runtime_dynamic_projection(
            getproperty(value, name))
    end
    return output
end

function known_truth_simulation_outputs(objects)
    values = (
        "local-dependence-simulation-grid" => objects.local_dependence_grid,
        "local-dependence-known-truth" => objects.local_dependence_known_truth,
        "local-dependence-calibration-contract" =>
            objects.local_dependence_calibration,
        "local-dependence-calibration-row" =>
            objects.local_dependence_calibration_result,
        "local-dependence-calibration-summary" =>
            objects.local_dependence_calibration_overview,
        "local-dependence-calibration-pilot-contract" =>
            objects.local_dependence_pilot_contract,
        "local-dependence-calibration-pilot-preflight" =>
            objects.local_dependence_pilot_preflight,
    )
    outputs = Pair{String,String}[]
    for (label, value) in values
        projected = runtime_dynamic_projection(value)
        push!(outputs, "simulation:$label:json" => JSON3.write(projected))
        push!(outputs, "simulation:$label:show" => sprint(show, projected))
    end
    return outputs
end

function synthetic_full_report()
    return (;
        schema = "bayesianmgmfrm.fit_report.v1",
        object = :fit_report,
        created_at = "2026-07-18T00:00:00",
        family = :mgmfrm,
        thresholds = :partial_credit,
        dimensions = 2,
        dimension_labels = ["dim=1", "dim=2"],
        estimation_status = :experimental_public,
        status_policy = (;
            next_gate = :private_review_step,
            publication_or_registration_action = false,
        ),
        metadata = (;
            backend = :advancedhmc,
            sampler = :nuts,
            guarded_local_fit = true,
            source_path = "/Users/example/private/report.json",
        ),
        posterior = (;
            status = :computed,
            n_rows = 1,
            rows = [(;
                parameter = "person[E1,dim=1]",
                mean = 0.0,
                fixture_provenance = "test/fixtures/private.json",
                internal_target_constructor = :_private_target,
                next_gate = :private_review_step,
            )],
        ),
    )
end

function report_outputs(objects)
    full_report = synthetic_full_report()
    public_report = fit_report_public(full_report)
    fit_report_public(public_report) === public_report ||
        error("fit_report_public must be idempotent")
    outputs = Pair{String,String}[
        "report:public-json" => JSON3.write(public_report),
        "report:public-show" => sprint(show, public_report),
        "report:public-markdown" => fit_report_markdown(public_report;
            max_rows = 2),
    ]
    report_options = (;
        include_prior_predictive = false,
        include_posterior_predictive = false,
        include_grouped_predictive = false,
        include_direct_posterior = false,
        include_calibration = false,
        include_waic = false,
        include_loo = false,
        include_dff = false,
        include_artifact = false,
    )
    actual_public_report = fit_report(objects.mfrm_fit;
        view = :public, report_options...)
    overload_public_report = fit_report_public(objects.mfrm_fit;
        view = :public, report_options...)
    assert_runtime_public_report_language([
        "report:public-structured" => public_report,
        "report:fit-view-public-structured" => actual_public_report,
        "report:fit-public-overload-structured" => overload_public_report,
    ])
    push!(outputs, "report:fit-view-public" =>
        JSON3.write(actual_public_report))
    push!(outputs, "report:fit-public-overload" =>
        JSON3.write(overload_public_report))
    mktempdir() do directory
        bundle = joinpath(directory, "public-report")
        save_fit_report_bundle(bundle, public_report)
        loaded = load_fit_report_bundle(bundle)
        loaded["schema"] == "bayesianmgmfrm.fit_report_public.v1" ||
            error("public fit-report bundle did not round-trip")
        assert_runtime_public_report_language([
            "report:bundle:loaded-structured" => loaded,
        ])
        for (root, _, files) in walkdir(bundle), file in sort(files)
            path = joinpath(root, file)
            content = read(path, String)
            occursin("source_path", content) &&
                error("public fit-report exports must omit source_path")
            push!(outputs,
                "report:bundle:$(relpath(path, bundle))" => content)
        end
    end

    dossier = fit_report_dossier(:reader => public_report)
    dossier_markdown = fit_report_dossier_markdown(dossier; max_rows = 2)
    assert_runtime_public_report_language([
        "dossier:structured" => dossier,
    ])
    push!(outputs, "dossier:json" => JSON3.write(dossier))
    push!(outputs, "dossier:show" => sprint(show, dossier))
    push!(outputs, "dossier:markdown" => dossier_markdown)
    mktempdir() do directory
        json_path = joinpath(directory, "dossier.json")
        markdown_path = joinpath(directory, "dossier.md")
        json_export = save_fit_report_dossier(json_path, dossier)
        markdown_export = save_fit_report_dossier_markdown(
            markdown_path, dossier; max_rows = 2)
        loaded_dossier = load_fit_report_dossier(json_path)
        assert_runtime_public_report_language([
            "dossier:export-loaded-structured" => loaded_dossier,
        ])
        push!(outputs, "dossier:export-json" => read(json_path, String))
        push!(outputs, "dossier:export-json-record" => JSON3.write(json_export))
        push!(outputs, "dossier:export-markdown" => read(markdown_path, String))
        push!(outputs, "dossier:export-markdown-record" =>
            JSON3.write(markdown_export))
    end
    return outputs
end

function captured_argument_error(f, label::String)
    try
        f()
    catch err
        err isa ArgumentError || error(
            "$label raised $(typeof(err)); expected ArgumentError")
        return label => sprint(showerror, err)
    end
    error("$label unexpectedly succeeded")
end

function error_outputs(objects)
    outputs = Pair{String,String}[]
    public_report = fit_report_public(synthetic_full_report())
    push!(outputs, captured_argument_error("error:report-schema") do
        fit_report_public((; schema = "unsupported.report.v1"))
    end)
    push!(outputs, captured_argument_error("error:mfrm-backend") do
        fit(objects.spec; backend = :unsupported_backend)
    end)
    push!(outputs, captured_argument_error("error:mgmfrm-prior") do
        fit(objects.mgmfrm_spec;
            experimental = true,
            prior = MFRMPrior(),
        )
    end)
    push!(outputs, captured_argument_error("error:mgmfrm-thresholds") do
        rating_scale_spec = mfrm_spec(objects.data;
            thresholds = :rating_scale,
            family = :mgmfrm,
            dimensions = 2,
            q_matrix = Bool[1 0; 0 1],
        )
        fit(rating_scale_spec; experimental = true)
    end)
    push!(outputs, captured_argument_error("error:report-markdown-rows") do
        fit_report_markdown(public_report; max_rows = -1)
    end)
    push!(outputs, captured_argument_error("error:report-section") do
        fit_report_section(public_report, :unsupported_section)
    end)
    push!(outputs, captured_argument_error("error:dossier-empty") do
        fit_report_dossier()
    end)
    push!(outputs, captured_argument_error("error:kfold-count") do
        kfold_plan(objects.data; k = 1)
    end)
    push!(outputs, captured_argument_error("error:posterior-interval") do
        posterior_summary(objects.mfrm_fit; lower = 0.5)
    end)
    push!(outputs, captured_argument_error("error:calibration-bins") do
        calibration_table(objects.mfrm_fit; bins = 0)
    end)
    return outputs
end

function main()
    objects = representative_objects()
    outputs = Pair{String,String}[]
    append!(outputs, exported_docstring_outputs())
    append!(outputs, show_outputs(objects))
    append!(outputs, clustered_diagnostic_outputs(objects))
    append!(outputs, known_truth_simulation_outputs(objects))
    append!(outputs, report_outputs(objects))
    append!(outputs, error_outputs(objects))
    result = assert_runtime_public_language(outputs)
    println("Runtime public language gate passed for $(result.n_surfaces) surfaces.")
    return nothing
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
