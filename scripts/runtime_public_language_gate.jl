#!/usr/bin/env julia

using BayesianMGMFRM
using JSON3
using Random

include(joinpath(@__DIR__, "public_language_gate.jl"))
using .PublicLanguageGate

const ROOT = abspath(normpath(joinpath(@__DIR__, "..")))

# These compatibility exports intentionally describe repository/release
# administration rather than reader-facing model results. Their full legacy
# views are tested separately; new public projections must not be added here.
const LEGACY_MAINTENANCE_EXPORTS = Set((
    :case_study_provenance_manifest,
    :evidence_artifact_schema_policy,
    :release_gate_check,
    :release_scope_summary,
))

# These fully qualified functions support developer research workflows. They
# are intentionally absent from the published manual. Exact study-ledger and
# recorded-output payloads remain unchanged.
const EXPERIMENTAL_DEVELOPER_DOCSTRINGS = Set((
    :free_latent_correlation_2d_known_truth_fixture,
    :free_latent_correlation_2d_oracle_profile,
    :free_latent_correlation_2d_recovery_pilot,
    :free_latent_correlation_2d_sampler_smoke,
    :free_latent_correlation_2d_study_apply_result,
    :free_latent_correlation_2d_study_dry_run,
    :free_latent_correlation_2d_study_feasibility_decision,
    :free_latent_correlation_2d_study_ledger,
    :free_latent_correlation_2d_study_plan,
    :free_latent_correlation_2d_study_resource_probe,
    :free_latent_correlation_2d_study_run_unit,
    :free_latent_correlation_2d_study_score,
    :free_latent_correlation_2d_study_unit_preflight,
))

function experimental_documented_names()
    implicit_module_bindings = Set((:Experimental, :eval, :include))
    candidates = names(BayesianMGMFRM.Experimental;
        all = true, imported = false)
    return sort!(filter(candidates) do name
        name in implicit_module_bindings && return false
        text = String(name)
        startswith(text, "_") && return false
        startswith(text, "#") && return false
        binding = Docs.Binding(BayesianMGMFRM.Experimental, name)
        Docs.doc(binding) !== nothing
    end; by = String)
end

function experimental_public_docstring_names()
    documented = Set(experimental_documented_names())
    contract = BayesianMGMFRM.Experimental.surface_contract()
    hasproperty(contract, :reader_facing_bindings) || error(
        "Experimental surface contract must declare reader_facing_bindings")
    declared = contract.reader_facing_bindings
    declared isa Tuple || error(
        "Experimental reader_facing_bindings must be a tuple")
    all(name -> name isa Symbol, declared) || error(
        "Experimental reader_facing_bindings must contain only symbols")
    length(unique(declared)) == length(declared) || error(
        "Experimental reader_facing_bindings contains duplicates")
    reader_facing = Set(declared)
    classified = union(
        reader_facing,
        EXPERIMENTAL_DEVELOPER_DOCSTRINGS,
    )
    overlap = intersect(
        reader_facing,
        EXPERIMENTAL_DEVELOPER_DOCSTRINGS,
    )
    isempty(overlap) || error(
        "Experimental docstring classifications overlap: $(sort!(collect(overlap); by=String))")
    documented == classified || error(
        "Experimental documented bindings must be classified exactly; " *
        "unclassified=$(sort!(collect(setdiff(documented, classified)); by=String)) " *
        "missing=$(sort!(collect(setdiff(classified, documented)); by=String))")
    return sort!(collect(reader_facing); by = String)
end

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
    experimental_names = experimental_public_docstring_names()
    isempty(experimental_names) &&
        error("no public Experimental docstrings were discovered")
    for name in experimental_names
        binding = Docs.Binding(BayesianMGMFRM.Experimental, name)
        doc = Docs.doc(binding)
        doc === nothing && error(
            "missing public Experimental docstring for $(String(name))")
        text = sprint(show, MIME"text/plain"(), doc)
        push!(outputs, "docstring:Experimental.$(String(name))" => text)
    end
    return outputs
end

function reader_facing_contract_outputs(objects)
    adversarial_environment_metadata = withenv(
        "GMFRM_POWER_NOTES" => "/Users/example/private-notes.txt",
    ) do
        evidence_metadata(; include_packages = false)
    end
    mfrm_metadata = fit_metadata(objects.mfrm_fit; view = :public)
    gmfrm_metadata = fit_metadata(objects.gmfrm_fit; view = :public)
    mgmfrm_metadata = fit_metadata(objects.mgmfrm_fit; view = :public)
    mfrm_diagnostics = diagnostics(objects.mfrm_fit; view = :public)
    gmfrm_diagnostics = diagnostics(objects.gmfrm_fit; view = :public)
    mgmfrm_diagnostics = diagnostics(objects.mgmfrm_fit; view = :public)
    gmfrm_metadata.estimation_status === :experimental || error(
        "public GMFRM fit metadata must report experimental availability")
    mgmfrm_metadata.estimation_status === :experimental || error(
        "public MGMFRM fit metadata must report experimental availability")
    for (label, surface) in (
            :gmfrm => gmfrm_diagnostics,
            :mgmfrm => mgmfrm_diagnostics)
        hasproperty(surface.summary, :raw_diagnostic_metrics) || error(
            "public $label diagnostics dropped raw-space metrics")
        hasproperty(surface.parameter_layout, :raw_parameter_names) || error(
            "public $label diagnostics dropped raw parameter names")
    end
    any(row -> row.value isa AbstractString &&
            occursin(r"^[0-9a-f]{64}$", row.value),
        mgmfrm_diagnostics.initialization_rows) && error(
            "public MGMFRM initialization rows expose identity hashes")

    sensitivity_baseline = (;
        sensitivity_axis = :thresholds,
        sensitivity_value = :partial_credit,
        baseline_value = :partial_credit,
        model = :partial_credit,
        baseline_model = :partial_credit,
        is_baseline = true,
        contrast = :baseline,
        criterion = :waic,
        elpd_difference_from_baseline = 0.0,
        information_criterion_difference_from_baseline = 0.0,
    )
    sensitivity_candidate = merge(sensitivity_baseline, (;
        sensitivity_value = :rating_scale,
        model = :rating_scale,
        is_baseline = false,
        contrast = :candidate,
    ))
    sensitivity_summary = sensitivity_comparison_summary(
        sensitivity_baseline,
        sensitivity_candidate;
        required_axes = (:thresholds,),
        view = :public,
    )
    sensitivity_summary.n_candidate_rows == 1 || error(
        "public sensitivity summary dropped candidate counts")
    only(sensitivity_summary.axis_rows).n_candidate_rows == 1 || error(
        "public sensitivity axis summary dropped candidate counts")

    comparison_rows = [
        comparison_evidence_row(;
            comparison_class = :stan,
            target_model = :mfrm_pcm,
            comparator = :reference_stan,
            metric = :log_density,
            estimate = 0.0,
            reference = 0.0,
            artifact = "private/results.json",
        ),
        comparison_evidence_row(;
            comparison_class = :facets,
            target_model = :mfrm_pcm,
            comparator = :facets_export,
            metric = :severity_correlation,
            estimate = 1.0,
            reference = 1.0,
            artifact = "/Users/example/private/results.json",
        ),
        comparison_evidence_row(;
            comparison_class = :nested,
            target_model = :scalar_gmfrm,
            comparator = :mfrm_pcm,
            metric = :heldout_elpd_difference,
            estimate = 1.0,
            reference = 0.0,
            pass_if = :greater_equal,
        ),
    ]
    comparison_summary = comparison_evidence_summary(
        comparison_rows;
        view = :public,
    )
    comparison_text = JSON3.write(runtime_dynamic_projection(
        comparison_summary))
    occursin("private/results.json", comparison_text) && error(
        "public comparison summary exposes artifact paths")

    benchmark_rows = (
        benchmark_result_row(;
            benchmark = :minimal_pcm_nuts,
            engine = :advancedhmc,
            model = :mfrm_pcm,
            elapsed_seconds = (1.0, 1.1, 0.9),
            effective_sample_sizes = (100.0, 110.0, 90.0),
        ),
        benchmark_result_row(;
            benchmark = :minimal_pcm_nuts,
            engine = :cmdstan,
            model = :stan_pcm,
            elapsed_seconds = (2.0, 2.1, 1.9),
            effective_sample_sizes = (80.0, 84.0, 76.0),
        ),
    )
    benchmark_gate = benchmark_summary(
        benchmark_rows...;
        view = :public,
    )
    simulation_rows = simulation_grid(;
        densities = (:sparse,),
        anchor_sizes = (0,),
        ratings_per_target = (1,),
        category_pathologies = (:none,),
        rater_noise = (:low,),
        dff = (:none,),
        dimensionalities = (1, 2),
        misspecifications = (:none, :omitted_dff),
        repetitions = 1,
        n_persons = 8,
        n_items = 2,
        n_raters = 2,
        n_categories = 3,
    )
    public_simulation_rows = simulation_grid(;
        densities = (:sparse,),
        anchor_sizes = (0,),
        ratings_per_target = (1,),
        category_pathologies = (:none,),
        rater_noise = (:low,),
        dff = (:none,),
        dimensionalities = (1, 2),
        misspecifications = (:none, :omitted_dff),
        repetitions = 1,
        n_persons = 8,
        n_items = 2,
        n_raters = 2,
        n_categories = 3,
        view = :public,
    )
    any(row -> row.dimensionality == 2 &&
            row.fit_surface === :fixed_q_confirmatory_mgmfrm_preview,
        public_simulation_rows) || error(
            "public simulation grid did not translate the 2D fit surface")
    any(row -> row.dimensionality == 1 &&
            row.misspecification === :omitted_dff &&
            row.fit_surface ===
                :mfrm_baseline_or_experimental_gmfrm_comparison,
        public_simulation_rows) || error(
            "public simulation grid did not translate the GMFRM comparison surface")
    occursin("guarded", JSON3.write(runtime_dynamic_projection(
        public_simulation_rows))) && error(
            "public simulation grid exposes implementation status wording")
    simulation_summary = simulation_grid_summary(
        simulation_rows;
        view = :public,
    )
    falsification_summary = falsification_rule_summary(
        falsification_rules();
        view = :public,
    )
    values = (
        "evidence-metadata" => evidence_metadata(; include_packages = false),
        "evidence-metadata:adversarial-env" =>
            adversarial_environment_metadata,
        "experimental-surface-contract" =>
            BayesianMGMFRM.Experimental.surface_contract(),
        "experimental-free-correlation-contract" =>
            BayesianMGMFRM.Experimental.free_latent_correlation_2d_contract(),
        "experimental-free-correlation-state" =>
            objects.free_correlation_state,
        "experimental-free-correlation-diagnostics" =>
            objects.free_correlation_diagnostics,
        "fit-metadata:MFRM" => mfrm_metadata,
        "fit-metadata:GMFRM" => gmfrm_metadata,
        "fit-metadata:MGMFRM" => mgmfrm_metadata,
        "diagnostics:MFRM" => mfrm_diagnostics,
        "diagnostics:GMFRM" => gmfrm_diagnostics,
        "diagnostics:MGMFRM" => mgmfrm_diagnostics,
        "sensitivity-comparison-summary" => sensitivity_summary,
        "comparison-evidence-summary" => comparison_summary,
        "benchmark-summary" => benchmark_gate,
        "simulation-grid" => public_simulation_rows,
        "simulation-grid-summary" => simulation_summary,
        "falsification-rule-summary" => falsification_summary,
        "model-equation:MGMFRM" => model_equation(objects.mgmfrm_spec),
        "fit-ready-parameter-layout:MFRM" =>
            fit_ready_parameter_layout(objects.design; view = :public),
        "fit-ready-parameter-layout:MGMFRM" =>
            fit_ready_parameter_layout(objects.preview; view = :public),
        "domain-compilation-summary:MFRM" =>
            domain_compilation_summary(objects.design; view = :public),
        "domain-compilation-summary:MGMFRM" =>
            domain_compilation_summary(objects.preview; view = :public),
        "domain-compilation-summary:anchor-path-redaction" =>
            domain_compilation_summary(
                objects.anchored_spec;
                preview = true,
                view = :public,
            ),
        "model-ladder" => model_ladder(view = :public),
        "rating-design-audit:anchor-path-redaction" =>
            rating_design_audit(objects.anchored_spec; view = :public),
        "anchor-linking-summary:anchor-path-redaction" =>
            anchor_linking_summary(objects.anchored_spec; view = :public),
        "related-software-capability-matrix" =>
            related_software_capability_matrix(view = :public),
        "model-manifest:MGMFRM" =>
            model_manifest(objects.preview; view = :public),
        "model-manifest:anchor-path-redaction" =>
            model_manifest(objects.anchored_spec; view = :public),
        "model-manifest:MFRM-fit" =>
            model_manifest(objects.mfrm_fit; view = :public),
        "model-manifest:MGMFRM-fit" =>
            model_manifest(objects.mgmfrm_fit; view = :public),
        "model-surface-audit:MGMFRM" =>
            model_surface_audit(objects.mgmfrm_spec; view = :public),
        "model-surface-audit:MGMFRM-fit" =>
            model_surface_audit(objects.mgmfrm_fit; view = :public),
        "fit-artifact:MFRM" => fit_artifact(
            objects.mfrm_fit;
            view = :public,
            include_environment = false,
        ),
        "fit-artifact:GMFRM" => fit_artifact(
            objects.gmfrm_fit;
            view = :public,
            include_environment = false,
        ),
        "fit-artifact:MGMFRM" => fit_artifact(
            objects.mgmfrm_fit;
            view = :public,
            include_environment = false,
        ),
        "anchor-declaration-validation" => anchor_refit_plan(objects.spec),
        "fit-reproduction-manifest" =>
            fit_reproduction_manifest(objects.mfrm_fit;
                view = :public,
                include_environment = false),
    )
    outputs = Pair{String,String}[]
    for (label, value) in values
        projected = runtime_dynamic_projection(value)
        push!(outputs, "contract:$label:json" => JSON3.write(projected))
        push!(outputs, "contract:$label:show" => sprint(show, projected))
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
    anchored_spec = mfrm_spec(data;
        thresholds = :partial_credit,
        anchors = [(;
            block = :rater,
            level = "R2",
            value = 0.25,
            type = :hard,
            source = :facets,
            source_version = "4.5.1",
            source_model = :mfrm_pcm,
            source_estimator = :jml,
            source_hash = repeat("0123456789abcdef", 4),
            source_scale = :logit,
            sign = :severity_positive,
            repository_path = "/Users/example/private-anchor.json",
            source_path = "/Users/example/private-source.json",
            file_path = "/Users/example/private-file.json",
        )],
    )
    design = getdesign(spec)
    clustered_spec = mfrm_spec(clustered_data; thresholds = :partial_credit)
    clustered_design = getdesign(clustered_spec)
    mgmfrm_spec = mfrm_spec(data;
        thresholds = :partial_credit,
        family = :mgmfrm,
        dimensions = 2,
        q_matrix = Bool[1 0; 0 1],
    )
    gmfrm_spec = mfrm_spec(data;
        thresholds = :partial_credit,
        family = :gmfrm,
        discrimination = :rater,
    )
    free_correlation_data = FacetData((;
        person = repeat(["E1", "E2", "E3", "E4"]; inner = 4),
        rater = [
            "R2", "R1", "R2", "R1",
            "R1", "R2", "R1", "R2",
            "R2", "R1", "R2", "R1",
            "R1", "R2", "R1", "R2",
        ],
        item = repeat(["I1", "I2", "I3", "I4"], 4),
        score = [
            0, 1, 2, 1,
            1, 2, 1, 0,
            2, 1, 0, 2,
            1, 0, 2, 1,
        ],
    );
        person = :person,
        rater = :rater,
        item = :item,
        score = :score,
    )
    free_correlation_spec = mfrm_spec(free_correlation_data;
        thresholds = :partial_credit,
        family = :mgmfrm,
        dimensions = 2,
        discrimination = :none,
        q_matrix = Bool[1 0; 0 1; 1 0; 0 1],
        dimension_labels = ["analytic", "verbal"],
    )
    free_correlation_candidate = BayesianMGMFRM.Experimental.
        free_latent_correlation_2d_candidate(free_correlation_spec)
    free_correlation_raw = initial_params(
        free_correlation_candidate;
        zrho = 0.2,
    )
    free_correlation_state = BayesianMGMFRM.Experimental.
        free_latent_correlation_2d_state(
            free_correlation_candidate,
            free_correlation_raw,
        )
    free_correlation_diagnostics = BayesianMGMFRM.Experimental.
        free_latent_correlation_2d_diagnostics(
            free_correlation_spec,
            free_correlation_raw;
            finite_difference_coords = (
                1,
                2,
                length(free_correlation_raw),
            ),
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
    generalized_smoke_controls = (;
        backend = :advancedhmc,
        ndraws = 1,
        warmup = 0,
        chains = 1,
        seed = 20260722,
        step_size = 0.02,
        max_depth = 1,
        metric = :unit,
    )
    gmfrm_fit = BayesianMGMFRM.Experimental.fit(
        gmfrm_spec;
        generalized_smoke_controls...,
    )
    mgmfrm_fit = BayesianMGMFRM.Experimental.fit(
        mgmfrm_spec;
        generalized_smoke_controls...,
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
        anchored_spec,
        design,
        mgmfrm_spec,
        preview,
        free_correlation_candidate,
        free_correlation_state,
        free_correlation_diagnostics,
        issue = isempty(validation.issues) ?
            ValidationIssue(:small_example, :warning,
                "The representative design is intentionally small.") :
            first(validation.issues),
        prior,
        target = MFRMLogDensity(design),
        mfrm_fit,
        gmfrm_fit,
        mgmfrm_fit,
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
        "ExperimentalFreeLatentCorrelation2DDensity" =>
            objects.free_correlation_candidate,
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
    append!(outputs, reader_facing_contract_outputs(objects))
    append!(outputs, report_outputs(objects))
    append!(outputs, error_outputs(objects))
    result = assert_runtime_public_language(outputs)
    println("Runtime public language gate passed for $(result.n_surfaces) surfaces.")
    return nothing
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
