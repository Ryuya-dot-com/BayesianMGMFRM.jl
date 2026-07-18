using Test
using BayesianMGMFRM
using JSON3

module PublicLanguageGateContractForTest

include(joinpath(@__DIR__, "..", "scripts", "public_language_gate.jl"))

end

const PublicLanguagePolicy = PublicLanguageGateContractForTest.PublicLanguageGate

@testset "public language release policy" begin
    root = abspath(normpath(joinpath(@__DIR__, "..")))
    result = PublicLanguagePolicy.check_public_language(root)

    @test result.passed
    @test result.n_language_violations == 0
    @test result.n_navigation_violations == 0
    @test result.n_workflow_violations == 0
    @test result.n_public_files == 17
    @test "scope.md" in PublicLanguagePolicy.PUBLIC_DOCUMENTATION_PAGES
    @test "roadmap.md" in PublicLanguagePolicy.DEVELOPER_DOCUMENTATION_PAGES
    for maintainer_name in (
            :case_study_provenance_manifest,
            :evidence_artifact_schema_policy,
            :evidence_metadata,
            :release_gate_check,
            :release_scope_summary)
        # Preserve the v0.1.x namespace even though published API pages do not
        # advertise these release and evidence helpers.
        @test maintainer_name in names(BayesianMGMFRM)
        @test isdefined(BayesianMGMFRM, maintainer_name)
    end

    restricted_runtime_values = (
        "SourceFixtureLogDensity",
        "PromotionCandidate",
        "guarded local fit",
        "candidate_gates",
        "caveat_docs_artifact",
        "publication_or_registration_action",
        "manuscript_claims_allowed",
        "public_claim_allowed",
        "package_default_change",
        "release_gate_check",
        "pre-registration",
        "manual public-scope",
        "local-only",
        "General AutoMerge",
        "registration handoff",
        "development ledgers",
        "registry-maintenance",
        "release-control",
        "worktree checking",
        "release handoff",
        "CI rendering",
        "artifacts/publication_grade/private.json",
        "after General registration",
        "fixture-SHA",
        "__private_helper",
        "/var/tmp/private.txt",
        "/workspace/private.txt",
    )
    additional_restricted_runtime_values = (
        "_θ",
        "```julia\n_private_helper()\n```",
        "guarded\nlocal\nfit",
        "registration\nhandoff",
        "/Volumes/private/report.json",
        "/mnt/private/report.json",
        raw"C:\Temp\private.txt",
        raw"\\server\private\report.json",
    )
    for value in (restricted_runtime_values...,
            additional_restricted_runtime_values...)
        @test !isempty(PublicLanguagePolicy.runtime_language_violations([
            "restricted runtime value" => value,
        ]))
    end
    for value in (
            "https://example.org/home/guide",
            "https://example.org/mnt/guide",
            "internal consistency",
            "_No rows to preview._",
            "_No tabular report rows are available._",
            "The model uses x_i and θ_i in this equation.")
        @test isempty(PublicLanguagePolicy.runtime_language_violations([
            "allowed runtime value" => value,
        ]))
    end

    mktempdir() do temp_root
        sample = joinpath(temp_root, "sample.md")
        write(sample, "Use `_private_helper` here.\nSee `test/fixtures/sample.json`.\n")
        violations = PublicLanguagePolicy.public_language_violations(
            temp_root; paths = [sample])
        @test Set(violation.rule for violation in violations) ==
            Set((:private_identifier, :developer_artifact_path))
    end

    mktempdir() do temp_root
        sample = joinpath(temp_root, "multiline.md")
        write(sample,
            "```julia\n_private_helper()\n_θ()\n```\nregistration\nhandoff\n")
        violations = PublicLanguagePolicy.public_language_violations(
            temp_root; paths = [sample])
        rules = Set(violation.rule for violation in violations)
        @test :private_identifier in rules
        @test :maintainer_workflow_wording in rules

        allowed = joinpath(temp_root, "allowed.md")
        write(allowed,
            "Internal consistency is a measurement term.\n" *
            "_No rows to preview._\n" *
            "The equation uses x_i and θ_i.\n")
        @test isempty(PublicLanguagePolicy.public_language_violations(
            temp_root; paths = [allowed]))
    end

    mktempdir() do temp_root
        allowed = joinpath(temp_root, "allowed.html")
        write(allowed,
            "<html><body>" *
            "<a target=\"_blank\" href=\"https://example.org/guide\">Guide</a>" *
            "<code>public_api</code>" *
            "<script>const _private_search_state = true;</script>" *
            "</body></html>\n")
        @test isempty(PublicLanguagePolicy.rendered_language_violations(
            temp_root; paths = [allowed]))

        restricted = joinpath(temp_root, "restricted.html")
        write(restricted,
            "<html><body><code>_private_helper</code> registration handoff" *
            "</body></html>\n")
        violations = PublicLanguagePolicy.rendered_language_violations(
            temp_root; paths = [restricted])
        rules = Set(violation.rule for violation in violations)
        @test :private_identifier in rules
        @test :rendered_private_identifier in rules
        @test :maintainer_workflow_wording in rules
    end

    mktempdir() do temp_root
        write(joinpath(temp_root, "README.md"), "# Safe\n")
        write(joinpath(temp_root, "NEWS.md"), "# Safe\n")
        nested_example = joinpath(temp_root, "examples", "nested", "demo.jl")
        mkpath(dirname(nested_example))
        write(nested_example, "println(\"reader-facing\")\n")
        docs_root = joinpath(temp_root, "docs", "src")
        mkpath(docs_root)
        for page in PublicLanguagePolicy.PUBLIC_DOCUMENTATION_PAGES
            write(joinpath(docs_root, page), "# Safe\n")
        end
        @test nested_example in PublicLanguagePolicy.public_surface_paths(temp_root)
    end

    mktempdir() do temp_root
        workflow_path = joinpath(temp_root, ".github", "workflows", "CI.yml")
        release_gate_path =
            joinpath(temp_root, "scripts", "pre_registration_gate.jl")
        mkpath(dirname(workflow_path))
        mkpath(dirname(release_gate_path))
        workflow = read(joinpath(root, ".github", "workflows", "CI.yml"), String)
        release_gate = read(
            joinpath(root, "scripts", "pre_registration_gate.jl"), String)
        write(workflow_path, workflow)
        write(release_gate_path, release_gate)
        @test isempty(PublicLanguagePolicy.release_workflow_violations(temp_root))

        commented_workflow = join((
            occursin("scripts/pre_registration_gate.jl", line) &&
            occursin("julia", line) ? "# " * line : line
            for line in split(workflow, '\n'; keepempty = true)), "\n")
        write(workflow_path, commented_workflow)
        violations = PublicLanguagePolicy.release_workflow_violations(temp_root)
        @test :ci_missing_release_verification_gate in
            Set(violation.rule for violation in violations)

        inline_comment_workflow = join((
            occursin("scripts/pre_registration_gate.jl", line) &&
            occursin("julia", line) ?
                replace(line, r"julia.*" =>
                    "julia --version # julia scripts/pre_registration_gate.jl") :
                line
            for line in split(workflow, '\n'; keepempty = true)), "\n")
        write(workflow_path, inline_comment_workflow)
        violations = PublicLanguagePolicy.release_workflow_violations(temp_root)
        @test :ci_missing_release_verification_gate in
            Set(violation.rule for violation in violations)

        write(workflow_path, workflow)
        write(release_gate_path, replace(release_gate,
            "runtime_language_violations(outputs)" =>
                "runtime_language_violations(Pair{String,String}[])"))
        violations = PublicLanguagePolicy.release_workflow_violations(temp_root)
        @test :release_gate_missing_example_runtime_scan in
            Set(violation.rule for violation in violations)

        commented_runtime_step = replace(release_gate,
            "step(\"Runtime public language gate\", runtime_public_language_check)" =>
                "# step(\"Runtime public language gate\", runtime_public_language_check)")
        write(release_gate_path, commented_runtime_step)
        violations = PublicLanguagePolicy.release_workflow_violations(temp_root)
        @test :release_gate_missing_runtime_language_gate in
            Set(violation.rule for violation in violations)
    end

    ratings = (
        examinee = ["E1", "E1", "E2", "E2"],
        rater = ["R1", "R2", "R1", "R2"],
        item = ["I1", "I1", "I1", "I1"],
        score = [0, 1, 1, 0],
    )
    data = FacetData(ratings;
        person = :examinee,
        rater = :rater,
        item = :item,
        score = :score,
    )
    design = getdesign(mfrm_spec(data; thresholds = :partial_credit))
    n_parameters = length(design.parameter_names)
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
    for fit_result in (
            GMFRMFit(generalized_args...),
            MGMFRMFit(generalized_args...))
        rendered = sprint(show, fit_result)
        @test occursin("status = :experimental", rendered)
        mktempdir() do temp_root
            output = joinpath(temp_root, "show.txt")
            write(output, rendered)
            @test isempty(PublicLanguagePolicy.public_language_violations(
                temp_root; paths = [output]))
        end
    end

    report = (;
        schema = "bayesianmgmfrm.fit_report.v1",
        object = :fit_report,
        created_at = "2026-07-18T00:00:00",
        family = :mgmfrm,
        thresholds = :partial_credit,
        dimensions = 2,
        estimation_status = :experimental_public,
        metadata = (;
            schema = "bayesianmgmfrm.mgmfrm_guarded_local_fit_diagnostics.v1",
            scope = :minimal_confirmatory_mgmfrm_candidate,
            fit_ready = true,
            sampler_controls = (;
                turing_model = :mfrm_logdensity_flat_parameter_model,
            ),
        ),
        posterior = (;
            status = :computed,
            n_rows = 1,
            rows = [(;
                parameter = "person[E1,dim=1]",
                mean = 0.0,
                next_gate = :private_review_step,
                internal_target_constructor = :_private_target,
            )],
        ),
    )
    markdown = fit_report_markdown(report)
    @test occursin("experimental", markdown)
    @test !occursin(r"experimental_public|guarded_local_fit|next_gate|internal_target_constructor|_private_target",
        markdown)

    public_report = fit_report_public(report)
    @test public_report.schema == "bayesianmgmfrm.fit_report_public.v1"
    @test public_report.object === :fit_report_public
    @test public_report.status === :experimental
    @test public_report.source_report.schema == report.schema
    @test public_report.source_report.content_hash ==
        BayesianMGMFRM._public_fit_report_content_hash_record(report).value
    @test !hasproperty(public_report, :status_policy)
    @test !hasproperty(public_report.metadata, :schema)
    @test !hasproperty(public_report.metadata, :scope)
    @test !hasproperty(public_report.metadata, :fit_ready)
    @test !hasproperty(public_report.metadata.sampler_controls, :turing_model)
    @test !hasproperty(public_report.posterior.rows[1], :next_gate)
    @test !hasproperty(public_report.posterior.rows[1],
        :internal_target_constructor)
    @test fit_report_public(public_report) === public_report
    @test fit_report_rows(public_report, :posterior) ===
        public_report.posterior.rows
    public_dossier = fit_report_dossier(:public => public_report)
    @test only(public_dossier.report_rows).estimation_status === :experimental
    @test only(public_dossier.report_rows).report_content_hash.value ==
        public_report.content_hash.value
    public_json = JSON3.write(public_report)
    @test isempty(PublicLanguagePolicy.runtime_language_violations([
        "synthetic public report" => public_json,
        "synthetic public Markdown" => fit_report_markdown(public_report),
    ]))
    @test !isempty(PublicLanguagePolicy.runtime_language_violations([
        "synthetic complete report" => JSON3.write(report),
    ]))
    for value in restricted_runtime_values
        restricted_report = merge(report, (;
            posterior = (;
                status = :computed,
                n_rows = 1,
                rows = [(; mean = 0.0, note = value)],
            ),
        ))
        restricted_public_report = fit_report_public(restricted_report)
        @test !hasproperty(restricted_public_report.posterior.rows[1], :note)
    end

    guarded_report = merge(report, (;
        estimation_status = :specified_only,
        status_policy = (;
            status_label = :experimental_public,
            next_gate = :private_review_step,
        ),
    ))
    guarded_public_report = fit_report_public(guarded_report)
    @test guarded_public_report.status === :experimental
    @test !hasproperty(guarded_public_report, :status_policy)

    user_label_report = merge(report, (;
        dimension_labels = ["_latent", "internal consistency"],
        posterior = (;
            status = :computed,
            n_rows = 1,
            warnings = ["reader-facing", "__private_helper"],
            rows = [(;
                parameter = "person[_E1]",
                item = "_respondent",
                mean = 0.0,
                step_path = ["category 1", "category 2"],
                note = "internal_promotion_candidate",
            )],
        ),
    ))
    user_label_public_report = fit_report_public(user_label_report)
    @test user_label_public_report.dimension_labels ==
        user_label_report.dimension_labels
    @test user_label_public_report.posterior.rows[1].parameter == "person[_E1]"
    @test user_label_public_report.posterior.rows[1].item == "_respondent"
    @test user_label_public_report.posterior.rows[1].step_path ==
        ["category 1", "category 2"]
    @test !hasproperty(user_label_public_report.posterior.rows[1], :note)
    @test length(user_label_public_report.posterior.warnings) == 2
    @test ismissing(user_label_public_report.posterior.warnings[2])
    @test isempty(
        PublicLanguagePolicy.runtime_public_report_language_violations([
            "public report with user labels" => user_label_public_report,
        ]))
    @test isempty(
        PublicLanguagePolicy.runtime_public_report_language_violations([
            "nested user label components" => (;
                level = (;
                    term = "_latent",
                    cell = ("internal consistency", "_respondent"),
                ),
            ),
        ]))
    @test isempty(
        PublicLanguagePolicy.runtime_public_report_language_violations([
            "reader step path" => (;
                step_path = ["_category 1", "internal consistency"],
            ),
        ]))
    for structured_value in (
            (; parameter = (; note = "release_gate_check")),
            (; parameter = [(; note = "release_gate_check")]))
        @test !isempty(
            PublicLanguagePolicy.runtime_public_report_language_violations([
                "structured user value" => structured_value,
            ]))
    end

    loaded_public_report = JSON3.read(JSON3.write(public_report))
    @test fit_report_public(loaded_public_report) === loaded_public_report
    for markdown_view in (
            fit_report_markdown(public_report),
            fit_report_markdown(loaded_public_report))
        @test occursin(public_report.content_hash.value, markdown_view)
    end
    loaded_full_report = JSON3.read(JSON3.write(
        BayesianMGMFRM._json_export_value(report)))
    loaded_full_public_report = fit_report_public(loaded_full_report)
    @test loaded_full_public_report.source_report.content_hash ==
        public_report.source_report.content_hash
    @test loaded_full_public_report.content_hash.value ==
        public_report.content_hash.value
    tampered_public_report = merge(public_report, (; status = :not_supported))
    @test_throws ArgumentError fit_report_public(tampered_public_report)
    @test_throws ArgumentError fit_report_public(
        merge(public_report, (; object = :fit_report)))
    @test_throws ArgumentError fit_report_public(
        merge(public_report, (; status = :private_status)))
    @test_throws ArgumentError fit_report_public(
        merge(public_report, (; source_report = missing)))
    for hash_record in (
            merge(public_report.content_hash, (; scope = :wrong_scope)),
            merge(public_report.content_hash,
                (; canonicalization = :wrong_canonicalization)),
            merge(public_report.content_hash, (; n_canonical_bytes = 0)),
            Base.structdiff(public_report.content_hash, (; scope = nothing)))
        @test_throws ArgumentError fit_report_public(
            merge(public_report, (; content_hash = hash_record)))
    end
    invalid_source_payload = merge(public_report, (;
        source_report = (;
            schema = public_report.source_report.schema,
            content_hash = "not-a-sha256",
        ),
    ))
    invalid_source_report = merge(invalid_source_payload, (;
        content_hash = BayesianMGMFRM._public_fit_report_content_hash_record(
            invalid_source_payload),
    ))
    @test_throws ArgumentError fit_report_public(invalid_source_report)
    nonfinite_report = merge(report, (;
        posterior = (;
            status = :computed,
            n_rows = 1,
            rows = [(; parameter = "person[E1]", mean = NaN)],
        ),
    ))
    nonfinite_public_report = fit_report_public(nonfinite_report)
    @test nonfinite_public_report.posterior.rows[1].mean == "NaN"
    @test JSON3.write(nonfinite_public_report) isa String

    mktempdir() do temp_root
        report_path = joinpath(temp_root, "public-report.json")
        export_record = save_fit_report(report_path, public_report)
        @test !hasproperty(export_record, :source_path)
        @test export_record.report_content_hash.value ==
            public_report.content_hash.value
        loaded_report = load_fit_report(report_path)
        @test fit_report_public(loaded_report) === loaded_report

        bundle_dir = joinpath(temp_root, "public-report")
        manifest = save_fit_report_bundle(bundle_dir, public_report)
        @test manifest.report_schema == public_report.schema
        @test manifest.report_content_hash.value ==
            public_report.content_hash.value
        @test !hasproperty(manifest, :source_path)
        loaded = load_fit_report_bundle(bundle_dir)
        @test loaded["schema"] == public_report.schema
        outputs = Pair{String,String}[]
        for (root, _, files) in walkdir(bundle_dir), file in files
            content = read(joinpath(root, file), String)
            @test !occursin("source_path", content)
            @test !occursin(temp_root, content)
            push!(outputs, relpath(joinpath(root, file), bundle_dir) => content)
        end
        @test isempty(PublicLanguagePolicy.runtime_language_violations(outputs))
    end
end
