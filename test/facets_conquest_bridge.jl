using Test
using BayesianMGMFRM
using JSON3
using LinearAlgebra
using SHA

function _bridge_test_table(; scores = nothing)
    persons = [
        "受験者,一",
        "受験者\n二",
        "受験者三",
        "受験者四",
        "受験者五",
        "受験者六",
    ]
    raters = ["採点者=甲", "採点者*乙", "採点者;丙"]
    items = ["課題;一", "課題,二", "課題=三"]
    cells = [(rater, item, category)
        for rater in eachindex(raters)
        for item in eachindex(items)
        for category in 0:2]
    observed_scores = scores === nothing ?
        [category for (_, _, category) in cells] : collect(scores)
    length(observed_scores) == length(cells) ||
        throw(ArgumentError("bridge test scores have the wrong length"))
    return (;
        person = [persons[mod1(rater + 2item + category, length(persons))]
            for (rater, item, category) in cells],
        rater = [raters[rater] for (rater, _, _) in cells],
        item = [items[item] for (_, item, _) in cells],
        score = observed_scores,
    )
end

function _bridge_test_data(table = _bridge_test_table())
    return FacetData(
        table;
        person = :person,
        rater = :rater,
        item = :item,
        score = :score,
    )
end

function _bridge_test_file(bundle, path::AbstractString)
    index = findfirst(file -> file.path == path, bundle.files)
    index === nothing && error("bridge test file is missing: $path")
    return bundle.files[index]
end

function _bridge_test_write(path::AbstractString, content::AbstractString)
    mkpath(dirname(path))
    open(path, "w") do io
        write(io, content)
    end
    return path
end

function _bridge_test_populate_results(root::AbstractString, bundle)
    for expected in bundle.manifest.expected_outputs
        content = if expected.role === :process_exit_code
            "0\n"
        elseif expected.role === :console_log
            ""
        elseif expected.role === :parameter_pairs
            "2 -0.25\n1 0.5\n"
        else
            "completed\n"
        end
        _bridge_test_write(
            joinpath(root, split(expected.path, '/')...), content)
    end
    return root
end

function _bridge_test_semantic_table()
    rows = [(rater, item, category)
        for item in 1:4 for rater in 1:3 for category in 0:2]
    return (;
        person = [
            "semantic-person-$(mod1(rater + 2item + category, 8))"
            for (rater, item, category) in rows
        ],
        rater = ["semantic-rater-$(rater)" for (rater, _, _) in rows],
        item = ["semantic-item-$(item)" for (_, item, _) in rows],
        score = [category for (_, _, category) in rows],
    )
end

function _bridge_test_populate_semantic_results(root::AbstractString, bundle,
        spec, parameter_content::AbstractString,
        design_content::AbstractString)
    for expected in bundle.manifest.expected_outputs
        content = if expected.role === :process_exit_code
            "0\n"
        elseif expected.role in (:console_log, :conquest_labels)
            ""
        elseif expected.role === :parameter_pairs
            String(parameter_content)
        elseif expected.role === :design_matrix
            String(design_content)
        else
            "completed\n"
        end
        _bridge_test_write(
            joinpath(root, split(expected.path, '/')...), content)
    end
    return root
end

function _bridge_test_rebind_manifest_id(manifest_text::AbstractString)
    pattern = r"\"bundle_id\":\"sha256:[0-9a-f]{64}\""
    matches = collect(eachmatch(pattern, manifest_text))
    length(matches) == 1 || error("test manifest has an unexpected bundle_id shape")
    sentinel_field = string(
        "\"bundle_id\":\"sha256:", repeat("0", 64), "\"")
    normalized = replace(
        String(manifest_text), matches[1].match => sentinel_field; count = 1)
    rebound_id = string(
        "sha256:", bytes2hex(sha256(codeunits(normalized))))
    rebound_field = string("\"bundle_id\":\"", rebound_id, "\"")
    return replace(normalized, sentinel_field => rebound_field; count = 1)
end

function _bridge_test_rmse(estimate, truth)
    length(estimate) == length(truth) ||
        error("bridge fixture vectors have different lengths")
    return sqrt(sum(abs2, estimate .- truth) / length(truth))
end

function _bridge_test_history(path::AbstractString)
    rows = [split(line, '\t') for line in eachline(path)]
    all(row -> length(row) >= 5, rows) ||
        error("ConQuest history fixture has fewer than five columns")
    return (;
        iteration = [parse(Int, row[2]) for row in rows],
        deviance = [parse(Float64, row[3]) for row in rows],
        population_variance = [parse(Float64, row[5]) for row in rows],
        raw = rows,
    )
end

function _bridge_test_design_matrix(path::AbstractString)
    lines = readlines(path)
    length(lines) > 1 || error("ConQuest design-matrix fixture is empty")
    header = split(first(lines), ',')
    body = [split(line, ',') for line in lines[2:end]]
    all(row -> length(row) == length(header), body) ||
        error("ConQuest design-matrix fixture has a ragged row")
    matrix = Matrix{Float64}(undef, length(body), length(header) - 2)
    for row_index in eachindex(body), column_index in 3:length(header)
        matrix[row_index, column_index - 2] =
            parse(Float64, strip(body[row_index][column_index]))
    end
    return (;
        header = strip.(header),
        gin = [parse(Int, strip(row[1])) for row in body],
        category = [parse(Int, strip(row[2])) for row in body],
        matrix,
    )
end

function _bridge_test_receipt_payload(receipt)
    parameter_export = (;
        parsed = receipt.parameter_export.parsed,
        n_parameter_pairs = receipt.parameter_export.n_parameter_pairs,
        semantic_parameter_identity_resolved =
            receipt.parameter_export.semantic_parameter_identity_resolved,
        source_sha256 = String(receipt.parameter_export.source_sha256),
    )
    output_files = Tuple((;
        path = String(output.path),
        role = Symbol(String(output.role)),
        nbytes = output.nbytes,
        sha256 = String(output.sha256),
    ) for output in receipt.output_files)
    return (;
        schema = String(receipt.schema),
        object = Symbol(String(receipt.object)),
        status = Symbol(String(receipt.status)),
        bundle_id = String(receipt.bundle_id),
        software = Symbol(String(receipt.software)),
        software_version = String(receipt.software_version),
        executable_sha256 = String(receipt.executable_sha256),
        executed_at_utc = String(receipt.executed_at_utc),
        exit_code = receipt.exit_code,
        input_manifest_sha256 = String(receipt.input_manifest_sha256),
        raw_return_integrity_verified =
            receipt.raw_return_integrity_verified,
        external_execution_completed = receipt.external_execution_completed,
        external_execution_reported_completed =
            receipt.external_execution_reported_completed,
        external_execution_independently_verified =
            receipt.external_execution_independently_verified,
        external_execution_authenticity_verified =
            receipt.external_execution_authenticity_verified,
        convergence_validated = receipt.convergence_validated,
        semantic_parameter_adapter_validated =
            receipt.semantic_parameter_adapter_validated,
        numerical_comparison_allowed = receipt.numerical_comparison_allowed,
        software_equivalence_claimed = receipt.software_equivalence_claimed,
        parameter_export,
        output_files,
    )
end

@testset "FACETS and ConQuest licensed-host bridge" begin
    data = _bridge_test_data()
    rsm = mfrm_spec(data; thresholds = :rating_scale)
    pcm = mfrm_spec(data; thresholds = :partial_credit)

    @testset "portable relative path normalization" begin
        relative_path = BayesianMGMFRM._external_bridge_relative_path
        @test relative_path("results/conquest_console.log") ==
            "results/conquest_console.log"
        @test relative_path(raw"results\conquest_console.log") ==
            "results/conquest_console.log"
        mixed_path = relative_path(raw"results\nested/conquest_console.log")
        @test mixed_path == "results/nested/conquest_console.log"
        @test !occursin('\\', mixed_path)
        for invalid in (
                "",
                "/results/conquest_console.log",
                raw"\results\conquest_console.log",
                raw"\\server\share\conquest_console.log",
                "C:/results/conquest_console.log",
                raw"C:results\conquest_console.log",
                "results//conquest_console.log",
                raw"results\\conquest_console.log",
                "results/./conquest_console.log",
                "results/../conquest_console.log",
                raw"results\..\conquest_console.log",
                "results/\0conquest_console.log",
                "results/",
            )
            @test_throws ArgumentError relative_path(invalid)
        end
    end

    @testset "RSM compilation, sparse preservation, and privacy defaults" begin
        facets = facets_bridge_bundle(rsm; title = "Portable FACETS RSM")
        conquest = conquest_bridge_bundle(rsm; title = "Portable ConQuest RSM")

        @test facets.software === :facets
        @test conquest.software === :conquest
        @test facets.status === :ready_for_licensed_host_execution
        @test conquest.status === :ready_for_licensed_host_execution
        @test !facets.external_execution_completed
        @test !conquest.external_execution_completed
        @test facets.manifest.model_target.threshold_regime === :rating_scale
        @test conquest.manifest.model_target.threshold_regime === :rating_scale

        facets_control = _bridge_test_file(facets, "facets_control.txt").content
        @test occursin("Models=?,?,?,R2K", facets_control)
        @test occursin("Positive=1", facets_control)
        @test occursin("Noncenter=1", facets_control)
        @test occursin("Data=facets_data.dat", facets_control)

        conquest_control =
            _bridge_test_file(conquest, "conquest_control.cqc").content
        @test occursin("model raterid + itemid + step;", conquest_control)
        @test occursin("filetype=csv", conquest_control)
        @test occursin("pid=personid", conquest_control)
        @test occursin("keeps=itemid raterid", conquest_control)
        @test occursin("codes A,B,C;", conquest_control)
        @test occursin("score (A,B,C) (0,1,2);", conquest_control)
        @test occursin("exit_on_error=yes", conquest_control)
        @test occursin("addextension=no", conquest_control)
        @test first(findfirst("estimate !", conquest_control)) <
            first(findfirst("export parameters", conquest_control))

        facets_rows = split(chomp(
            _bridge_test_file(facets, "facets_data.dat").content), "\r\n")
        conquest_rows = split(chomp(
            _bridge_test_file(conquest, "conquest_ratings.csv").content),
            "\r\n")
        facets_map_rows = split(chomp(
            _bridge_test_file(facets, "observation_map.tsv").content), "\n")
        conquest_map_rows = split(chomp(
            _bridge_test_file(conquest, "observation_map.tsv").content), "\n")
        @test length(facets_rows) == data.n
        @test length(conquest_rows) == data.n + 1
        @test length(facets_map_rows) == data.n + 1
        @test length(conquest_map_rows) == data.n + 1
        @test facets.manifest.data.n_ratings == data.n
        @test conquest.manifest.data.n_ratings == data.n
        @test facets.manifest.data.rows_added == 0
        @test facets.manifest.data.rows_removed == 0
        @test conquest.manifest.data.rows_added == 0
        @test conquest.manifest.data.rows_removed == 0
        @test !facets.manifest.execution.macos_runner_included
        @test conquest.manifest.execution.macos_runner_included
        conquest_labels_contract = only(filter(
            output -> output.role === :conquest_labels,
            conquest.manifest.expected_outputs,
        ))
        @test conquest_labels_contract.required
        @test conquest_labels_contract.allow_empty
        @test all(output ->
                output.role in (:console_log, :conquest_labels) ||
                    !output.allow_empty,
            conquest.manifest.expected_outputs)
        legacy_outputs =
            BayesianMGMFRM._external_bridge_manifest_expected_outputs(Dict(
                "expected_outputs" => [
                    Dict(
                        "path" => "results/conquest_console.log",
                        "role" => "console_log",
                        "required" => true,
                    ),
                    Dict(
                        "path" => "results/conquest_labels.txt",
                        "role" => "conquest_labels",
                        "required" => true,
                    ),
                ],
            ))
        @test legacy_outputs[1].allow_empty
        @test !legacy_outputs[2].allow_empty
        @test data.n < length(data.person_levels) *
            length(data.rater_levels) * length(data.item_levels)

        macos_verifier =
            _bridge_test_file(conquest, "verify_bundle_macos.sh")
        macos_runner = _bridge_test_file(conquest, "run_conquest_macos.sh")
        @test macos_verifier.role === :macos_input_verifier
        @test macos_runner.role === :macos_runner
        @test conquest.host_preflight.macos_verifier ==
            (; path = macos_verifier.path, sha256 = macos_verifier.sha256)
        @test conquest.host_preflight.macos_runner ==
            (; path = macos_runner.path, sha256 = macos_runner.sha256)
        @test !haskey(facets.host_preflight, :macos_verifier)
        @test !haskey(facets.host_preflight, :macos_runner)
        @test occursin("BRIDGE_BUNDLE_ID", macos_verifier.content)
        @test occursin("results must be empty before external execution",
            macos_verifier.content)
        @test occursin("unset DYLD_INSERT_LIBRARIES", macos_runner.content)
        @test occursin("\"\$CONQUEST_EXE\" \"conquest_control.cqc\"",
            macos_runner.content)
        @test _bridge_test_file(
            conquest, "verify_bundle_windows.ps1").sha256 ==
            "f64351b4899d256202b838fb13f101a2a3acfebe89709e3a720793b0b8b1efc7"
        @test _bridge_test_file(
            conquest, "run_conquest_windows.cmd").sha256 ==
            "fff3a9e2e3da950451cd164223b80690cb595387dc8a97e3002ee5859ef77764"
        @test _bridge_test_file(
            facets, "run_facets_windows.cmd").sha256 ==
            "35ecfb572aef63b64466a15cdafbe61430402118211be67276bff2946d7eb120"

        labels = vcat(data.person_levels, data.rater_levels, data.item_levels)
        for bundle in (facets, conquest)
            transfer_text = join((file.content for file in bundle.files), "\n")
            @test all(label -> !occursin(string(label), transfer_text), labels)
            id_map = _bridge_test_file(bundle, "id_map.tsv").content
            @test occursin("canonical_label_sha256", id_map)
            @test bundle.manifest.privacy.canonical_label_hashes_included
            @test !bundle.manifest.privacy.original_labels_included
            @test bundle.manifest.privacy.label_hash_input ===
                :canonical_label_representation_v1
            @test bundle.manifest.privacy.label_hashes_are_unsalted
            @test bundle.manifest.privacy.label_hashes_are_pseudonymous
            @test !bundle.manifest.privacy.anonymization_claimed
            @test !bundle.manifest.privacy.dictionary_resistance_claimed
            @test !bundle.manifest.evidence_boundary.host_bootstrap_authentication_verified
            @test !bundle.manifest.evidence_boundary.adversarial_transfer_protection_claimed
            @test !bundle.manifest.evidence_boundary.windows_powershell_5_execution_validated
            @test bundle.host_preflight.bundle_id == bundle.bundle_id
            @test bundle.host_preflight.verifier.sha256 ==
                _bridge_test_file(bundle, "verify_bundle_windows.ps1").sha256
            runner_name = bundle.software === :facets ?
                "run_facets_windows.cmd" : "run_conquest_windows.cmd"
            @test bundle.host_preflight.runner.sha256 ==
                _bridge_test_file(bundle, runner_name).sha256
            @test bundle.host_preflight.independent_operator_comparison_required
            @test !bundle.host_preflight.transfer_contained_launcher_is_trust_anchor
            @test !bundle.host_preflight.adversarial_transfer_protection_claimed
            bundle_readme = _bridge_test_file(bundle, "README.txt").content
            @test occursin("pseudonymization, not anonymization", bundle_readme)
            @test occursin("dictionary matched", bundle_readme)
            @test occursin("linked across bundles", bundle_readme)
        end

        labelled = facets_bridge_bundle(
            rsm;
            title = "Portable FACETS RSM labelled",
            include_original_labels = true,
        )
        @test labelled.manifest.privacy.original_labels_included
        @test labelled.manifest.privacy.label_hashes_are_unsalted
        @test !labelled.manifest.privacy.anonymization_claimed
        @test occursin("受験者,一",
            _bridge_test_file(labelled, "id_map.tsv").content)
        @test occursin("This bundle is not anonymized",
            _bridge_test_file(labelled, "README.txt").content)

        labelled_conquest = conquest_bridge_bundle(
            rsm;
            title = "Portable ConQuest RSM labelled",
            include_original_labels = true,
        )
        @test labelled_conquest.manifest.privacy.original_labels_included
        @test labelled_conquest.manifest.privacy.label_hashes_are_pseudonymous
        @test !labelled_conquest.manifest.privacy.anonymization_claimed
    end

    @testset "PCM compilation and deterministic identity" begin
        facets = facets_bridge_bundle(pcm; title = "Portable FACETS PCM")
        conquest = conquest_bridge_bundle(pcm; title = "Portable ConQuest PCM")
        facets_again = facets_bridge_bundle(pcm; title = "Portable FACETS PCM")
        conquest_again = conquest_bridge_bundle(pcm; title = "Portable ConQuest PCM")

        @test occursin("Models=?,?,#,R2K",
            _bridge_test_file(facets, "facets_control.txt").content)
        @test occursin("model raterid + itemid + itemid*step;",
            _bridge_test_file(conquest, "conquest_control.cqc").content)
        @test facets.manifest.model_target.threshold_regime === :partial_credit
        @test conquest.manifest.model_target.threshold_regime === :partial_credit
        @test facets.bundle_id == facets_again.bundle_id
        @test conquest.bundle_id == conquest_again.bundle_id
        @test [(file.path, file.sha256, file.nbytes) for file in facets.files] ==
            [(file.path, file.sha256, file.nbytes) for file in facets_again.files]
        @test [(file.path, file.sha256, file.nbytes) for file in conquest.files] ==
            [(file.path, file.sha256, file.nbytes) for file in conquest_again.files]

        recoded_data = _bridge_test_data(_bridge_test_table(
            scores = [score - 1 for score in _bridge_test_table().score],
        ))
        recoded = conquest_bridge_bundle(
            mfrm_spec(recoded_data; thresholds = :partial_credit);
            title = "Portable ConQuest recode",
        )
        category_map = _bridge_test_file(recoded, "category_map.tsv").content
        @test occursin("1\t-1\t0\tA", category_map)
        @test occursin("2\t0\t1\tB", category_map)
        @test occursin("3\t1\t2\tC", category_map)
    end

    @testset "fail-closed model boundaries" begin
        generalized = mfrm_spec(
            data;
            family = :gmfrm,
            thresholds = :partial_credit,
            discrimination = :rater,
        )
        @test_throws ArgumentError facets_bridge_bundle(generalized)
        @test_throws ArgumentError conquest_bridge_bundle(generalized)

        anchored = mfrm_spec(
            data;
            thresholds = :partial_credit,
            anchors = [(;
                block = :rater,
                level = first(data.rater_levels),
                value = 0.0,
                type = :hard,
            )],
        )
        @test_throws ArgumentError facets_bridge_bundle(anchored)
        @test_throws ArgumentError conquest_bridge_bundle(anchored)

        source = _bridge_test_table()
        duplicated = (;
            person = vcat(source.person, source.person[1]),
            rater = vcat(source.rater, source.rater[1]),
            item = vcat(source.item, source.item[1]),
            score = vcat(source.score, source.score[1]),
        )
        duplicate_spec = mfrm_spec(
            _bridge_test_data(duplicated);
            thresholds = :rating_scale,
        )
        @test_throws ArgumentError conquest_bridge_bundle(duplicate_spec)
        @test facets_bridge_bundle(duplicate_spec).software === :facets

        source_scores = _bridge_test_table().score
        source_items = _bridge_test_table().item
        pcm_hole_scores = [
            item == "課題;一" && score == 1 ? 2 : score
            for (item, score) in zip(source_items, source_scores)
        ]
        pcm_hole = mfrm_spec(
            _bridge_test_data(_bridge_test_table(scores = pcm_hole_scores));
            thresholds = :partial_credit,
        )
        @test_throws ArgumentError conquest_bridge_bundle(pcm_hole)
        @test facets_bridge_bundle(pcm_hole).software === :facets

        category_source = _bridge_test_table()
        one_cell_lacks_top = copy(category_source.score)
        one_cell_lacks_top[3] = 1
        incomplete_conquest = mfrm_spec(
            _bridge_test_data(_bridge_test_table(scores = one_cell_lacks_top));
            thresholds = :rating_scale,
        )
        @test_throws ArgumentError conquest_bridge_bundle(incomplete_conquest)
        @test facets_bridge_bundle(incomplete_conquest).software === :facets

        one_item_lacks_top = [
            item == "課題;一" && score == 2 ? 1 : score
            for (item, score) in zip(category_source.item, category_source.score)
        ]
        incomplete_facets_pcm = mfrm_spec(
            _bridge_test_data(_bridge_test_table(scores = one_item_lacks_top));
            thresholds = :partial_credit,
        )
        @test_throws ArgumentError facets_bridge_bundle(incomplete_facets_pcm)
    end

    @testset "saved input validation and tamper detection" begin
        bundle = facets_bridge_bundle(pcm; title = "Saved FACETS PCM")
        verifier = _bridge_test_file(bundle, "verify_bundle_windows.ps1").content
        runner = _bridge_test_file(bundle, "run_facets_windows.cmd").content
        @test occursin("BRIDGE_BUNDLE_ID", verifier)
        @test occursin(raw"$BundleIdPattern", verifier)
        @test occursin("('0' * 64)", verifier)
        @test occursin("complete manifest contract", verifier)
        @test occursin("[Text.Encoding]::UTF8.GetBytes", verifier)
        @test occursin("ReparsePoint", verifier)
        @test occursin("results must be empty before external execution", verifier)
        @test first(findfirst("verify_bundle_windows.ps1", runner)) <
            first(findfirst("%FACETS_EXE%", runner))
        @test occursin(".bridge_execution.lock", runner)

        mktempdir() do root
            validation = save_external_bridge_bundle(root, bundle)
            @test validation.valid
            @test validation.status === :input_bundle_valid
            @test validation.bundle_id == bundle.bundle_id
            @test validation.software === :facets
            @test validation.n_input_files == length(bundle.manifest.input_files)
            @test validation.host_preflight == bundle.host_preflight
            @test validate_external_bridge_bundle(
                root;
                expected_bundle_id = bundle.bundle_id,
            ).valid
            @test_throws ArgumentError validate_external_bridge_bundle(
                root;
                expected_bundle_id = "sha256:" * repeat("0", 64),
            )

            open(joinpath(root, "facets_data.dat"), "a") do io
                write(io, "1,1,1,0\r\n")
            end
            @test_throws ArgumentError validate_external_bridge_bundle(
                root;
                expected_bundle_id = bundle.bundle_id,
            )
        end

        mktempdir() do root
            save_external_bridge_bundle(root, bundle)
            @test_throws ArgumentError save_external_bridge_bundle(root, bundle)
            @test save_external_bridge_bundle(
                root, bundle; overwrite = true).valid
            mkpath(joinpath(root, "results"))
            @test save_external_bridge_bundle(
                root, bundle; overwrite = true).valid

            marker_path = joinpath(root, "README.txt")
            _bridge_test_write(marker_path, "must remain unchanged\n")
            _bridge_test_write(joinpath(root, "stale_runner.cmd"), "stale\r\n")
            @test_throws ArgumentError save_external_bridge_bundle(
                root, bundle; overwrite = true)
            @test read(marker_path, String) == "must remain unchanged\n"
        end

        mktempdir() do root
            save_external_bridge_bundle(root, bundle)
            _bridge_test_write(joinpath(root, "results"), "not a directory\n")
            @test_throws ArgumentError save_external_bridge_bundle(
                root, bundle; overwrite = true)
        end

        mktempdir() do root
            save_external_bridge_bundle(root, bundle)
            _bridge_test_write(
                joinpath(root, "results", "old_output.txt"), "stale\n")
            @test_throws ArgumentError save_external_bridge_bundle(
                root, bundle; overwrite = true)
        end

        mktempdir() do root
            save_external_bridge_bundle(root, bundle)
            marker_path = joinpath(root, "README.txt")
            _bridge_test_write(marker_path, "must remain unchanged\n")
            malformed = merge(bundle, (;
                bundle_id = "sha256:" * repeat("f", 64),
            ))
            @test_throws ArgumentError save_external_bridge_bundle(
                root, malformed; overwrite = true)
            @test read(marker_path, String) == "must remain unchanged\n"
        end

        mktempdir() do root
            save_external_bridge_bundle(root, bundle)
            manifest_path = joinpath(root, "bridge_manifest.json")
            original = read(manifest_path, String)
            tampered_contract = replace(
                original,
                "\"required\":true" => "\"required\":false";
                count = 1,
            )
            @test tampered_contract != original
            tampered = _bridge_test_rebind_manifest_id(tampered_contract)
            _bridge_test_write(manifest_path, tampered)
            ledger = string(bytes2hex(sha256(codeunits(tampered))),
                "  bridge_manifest.json\r\n")
            _bridge_test_write(joinpath(root, "bridge_manifest.sha256"), ledger)
            self_consistent = validate_external_bridge_bundle(root)
            @test self_consistent.valid
            @test self_consistent.bundle_id != bundle.bundle_id
            @test_throws ArgumentError validate_external_bridge_bundle(
                root;
                expected_bundle_id = bundle.bundle_id,
            )
        end

        if !Sys.iswindows()
            mktempdir() do root
                save_external_bridge_bundle(root, bundle)
                hardlink(joinpath(root, "facets_data.dat"),
                    joinpath(root, "facets_data.hardlink"))
                @test_throws ArgumentError validate_external_bridge_bundle(
                    root;
                    expected_bundle_id = bundle.bundle_id,
                )
            end

            mktempdir() do root
                save_external_bridge_bundle(root, bundle)
                readme_path = joinpath(root, "README.txt")
                control_path = joinpath(root, "facets_control.txt")
                rm(readme_path)
                hardlink(joinpath(root, "facets_data.dat"), readme_path)
                _bridge_test_write(control_path, "must remain unchanged\r\n")
                @test_throws ArgumentError save_external_bridge_bundle(
                    root, bundle; overwrite = true)
                @test read(control_path, String) == "must remain unchanged\r\n"
            end
        end
    end

    @testset "macOS ConQuest verifier and runner" begin
        conquest = conquest_bridge_bundle(
            rsm; title = "macOS ConQuest runner test")
        if Sys.isapple()
            mktempdir() do executable_root
                fake = _bridge_test_write(
                    joinpath(executable_root, "fake-conquest"),
                    raw"""#!/bin/sh
printf 'cwd=%s\n' "$PWD"
printf 'arg1=%s\n' "$1"
printf 'stderr-marker\n' >&2
exit 0
""",
                )
                chmod(fake, 0o700)

                mktempdir() do root
                    save_external_bridge_bundle(root, conquest)
                    verifier_command = addenv(
                        Cmd(`/bin/sh verify_bundle_macos.sh`; dir = root),
                        "BRIDGE_BUNDLE_ID" => conquest.bundle_id,
                    )
                    @test success(run(ignorestatus(verifier_command)))

                    runner_command = addenv(
                        Cmd(`/bin/sh run_conquest_macos.sh`; dir = root),
                        "BRIDGE_BUNDLE_ID" => conquest.bundle_id,
                        "CONQUEST_EXE" => fake,
                    )
                    @test success(run(ignorestatus(runner_command)))
                    console = read(joinpath(
                        root, "results", "conquest_console.log"), String)
                    @test occursin("cwd=$(realpath(root))", console)
                    @test occursin("arg1=conquest_control.cqc", console)
                    @test occursin("stderr-marker", console)
                    @test read(joinpath(
                        root, "results", "external_exit_code.txt"), String) ==
                        "0\n"
                    @test !ispath(joinpath(root, ".bridge_execution.lock"))
                    @test !success(run(ignorestatus(runner_command)))
                end

                mktempdir() do root
                    save_external_bridge_bundle(root, conquest)
                    wrong_id = addenv(
                        Cmd(`/bin/sh verify_bundle_macos.sh`; dir = root),
                        "BRIDGE_BUNDLE_ID" =>
                            "sha256:" * repeat("0", 64),
                    )
                    @test !success(run(ignorestatus(wrong_id)))
                    open(joinpath(root, "conquest_control.cqc"), "a") do io
                        write(io, "/* tampered */\n")
                    end
                    verifier_command = addenv(
                        Cmd(`/bin/sh verify_bundle_macos.sh`; dir = root),
                        "BRIDGE_BUNDLE_ID" => conquest.bundle_id,
                    )
                    @test !success(run(ignorestatus(verifier_command)))
                end

                failing_fake = _bridge_test_write(
                    joinpath(executable_root, "failing-conquest"),
                    "#!/bin/sh\nprintf 'controlled failure\\n'\nexit 7\n",
                )
                chmod(failing_fake, 0o700)
                mktempdir() do root
                    save_external_bridge_bundle(root, conquest)
                    runner_command = addenv(
                        Cmd(`/bin/sh run_conquest_macos.sh`; dir = root),
                        "BRIDGE_BUNDLE_ID" => conquest.bundle_id,
                        "CONQUEST_EXE" => failing_fake,
                    )
                    process = run(ignorestatus(runner_command))
                    @test process.exitcode == 7
                    @test read(joinpath(
                        root, "results", "external_exit_code.txt"), String) ==
                        "7\n"
                    @test !ispath(joinpath(root, ".bridge_execution.lock"))
                end
            end
        else
            @test occursin("/bin/sh",
                _bridge_test_file(
                    conquest, "run_conquest_macos.sh").content)
        end
    end

    @testset "ConQuest positional parameter parser" begin
        mktempdir() do root
            path = _bridge_test_write(
                joinpath(root, "parameters.txt"),
                "3 -1.25e0\r\n1 0.5\r\n\r\n2 0",
            )
            expected_hash = bytes2hex(sha256(read(path)))
            rows = load_conquest_parameter_export(
                path;
                expected_sha256 = expected_hash,
            )
            @test [row.parameter_number for row in rows] == [1, 2, 3]
            @test [row.value for row in rows] == [0.5, 0.0, -1.25]
            @test all(row -> !row.semantic_parameter_identity_resolved, rows)
            @test all(row -> row.source_comment === nothing, rows)
            @test_throws ArgumentError load_conquest_parameter_export(
                path;
                expected_sha256 = repeat("0", 64),
            )

            actual = _bridge_test_write(
                joinpath(root, "actual-conquest-5.47.5.txt"),
                string(
                    "3       1.00000         /* step 1 */\r\n",
                    "1       -0.48064        /* raterid R000001 */\r\n",
                    "2       0.25000         /* itemid I000002 */\r\n",
                ),
            )
            actual_rows = load_conquest_parameter_export(actual)
            @test [row.parameter_number for row in actual_rows] == [1, 2, 3]
            @test [row.value for row in actual_rows] == [-0.48064, 0.25, 1.0]
            @test [row.source_comment for row in actual_rows] ==
                ["raterid R000001", "itemid I000002", "step 1"]
            @test all(row -> !row.semantic_parameter_identity_resolved,
                actual_rows)

            duplicate = _bridge_test_write(
                joinpath(root, "duplicate.txt"), "1 0.5\n1 0.6\n")
            nonfinite = _bridge_test_write(
                joinpath(root, "nonfinite.txt"), "1 NaN\n")
            header = _bridge_test_write(
                joinpath(root, "header.txt"), "parameter value\n1 0.5\n")
            empty = _bridge_test_write(joinpath(root, "empty.txt"), "\n")
            overlong = _bridge_test_write(
                joinpath(root, "overlong.txt"),
                string("1 0", repeat(" ", 4094), "\n"),
            )
            @test_throws ArgumentError load_conquest_parameter_export(duplicate)
            @test_throws ArgumentError load_conquest_parameter_export(nonfinite)
            @test_throws ArgumentError load_conquest_parameter_export(header)
            @test_throws ArgumentError load_conquest_parameter_export(empty)
            @test_throws ArgumentError load_conquest_parameter_export(overlong)

            malformed_rows = (
                "1 0 arbitrary extra token\n",
                "1 0/* raterid R000001 */\n",
                "1 0 /* unterminated\n",
                "1 0 /* nested /* comment */\n",
                "1 0 /* first */ /* second */\n",
                "1 0 /* closed */ trailing\n",
                "1 0 /* line one\nline two */\n",
                "1 0 /* nonprintable \0 comment */\n",
                "0 0 /* nonpositive */\n",
                "-1 0 /* nonpositive */\n",
                "1 NaN /* nonfinite */\n",
                "1 Inf /* nonfinite */\n",
                "1 -Inf /* nonfinite */\n",
                "0x10 1 /* Julia-only hexadecimal integer */\n",
                "1 0x1p0 /* Julia-only hexadecimal float */\n",
                "1 0 /* duplicate first */\n1 1 /* duplicate second */\n",
            )
            for (index, content) in pairs(malformed_rows)
                malformed = _bridge_test_write(
                    joinpath(root, "malformed-$(index).txt"), content)
                @test_throws ArgumentError load_conquest_parameter_export(
                    malformed)
            end

            boundary_line = string("1 0", repeat(" ", 4093))
            @test ncodeunits(boundary_line) == 4096
            for (name, terminator) in (
                    ("boundary-no-newline.txt", ""),
                    ("boundary-lf.txt", "\n"),
                    ("boundary-crlf.txt", "\r\n"),
                )
                boundary = _bridge_test_write(
                    joinpath(root, name), string(boundary_line, terminator))
                boundary_rows = load_conquest_parameter_export(boundary)
                @test length(boundary_rows) == 1
                @test only(boundary_rows).value == 0.0
            end
            split_crlf = _bridge_test_write(
                joinpath(root, "boundary-split-crlf.txt"),
                string(
                    repeat("\n",
                        BayesianMGMFRM._EXTERNAL_BRIDGE_STREAM_CHUNK_BYTES -
                            ncodeunits(boundary_line) - 1),
                    boundary_line,
                    "\r\n",
                ),
            )
            split_rows = load_conquest_parameter_export(split_crlf)
            @test length(split_rows) == 1
            @test only(split_rows).value == 0.0
        end
    end

    @testset "ConQuest 5.47.5 semantic parameter adapter" begin
        semantic_data = FacetData(
            _bridge_test_semantic_table();
            person = :person,
            rater = :rater,
            item = :item,
            score = :score,
        )
        renamed_table = _bridge_test_semantic_table()
        renamed_data = FacetData(
            merge(renamed_table, (;
                rater = [value == "semantic-rater-1" ?
                    "renamed-rater-1" : value for value in renamed_table.rater],
            ));
            person = :person,
            rater = :rater,
            item = :item,
            score = :score,
        )
        fixture_root = joinpath(
            @__DIR__, "fixtures", "conquest_5_47_5")
        cases = (
            (;
                name = "rsm",
                thresholds = :rating_scale,
                expected_rater = [-0.48064, -0.01241, 0.49305],
                expected_item = [-0.63820, -0.21705, 0.14364, 0.71161],
                expected_thresholds = [-0.71581, 0.71581],
                expected_free = 6,
                expected_rows = 9,
            ),
            (;
                name = "pcm",
                thresholds = :partial_credit,
                expected_rater = [-0.35313, -0.04979, 0.40292],
                expected_item = [-0.58169, -0.12919, 0.16438, 0.54650],
                expected_thresholds = [
                    [-0.68676, 0.68676],
                    [-0.49813, 0.49813],
                    [-0.42007, 0.42007],
                    [-0.10561, 0.10561],
                ],
                expected_free = 9,
                expected_rows = 15,
            ),
        )
        for case in cases
            spec = mfrm_spec(semantic_data; thresholds = case.thresholds)
            renamed_spec = mfrm_spec(
                renamed_data; thresholds = case.thresholds)
            bundle = conquest_bridge_bundle(
                spec; title = "Semantic adapter $(uppercase(case.name))")
            parameters = read(joinpath(
                fixture_root, "$(case.name)_parameters.txt"), String)
            design_matrix = read(joinpath(
                fixture_root, "$(case.name)_designmatrix.csv"), String)
            mktempdir() do root
                save_external_bridge_bundle(root, bundle)
                _bridge_test_populate_semantic_results(
                    root, bundle, spec, parameters, design_matrix)
                semantic = load_conquest_semantic_parameters(
                    root,
                    spec;
                    expected_bundle_id = bundle.bundle_id,
                    software_version =
                        "ConQuest 5.47.5 Demonstration Version",
                    executable_sha256 = repeat("a", 64),
                    executed_at_utc = "2026-07-21T12:56:07Z",
                )
                @test semantic.schema ==
                    "bayesianmgmfrm.conquest_semantic_parameters.v1"
                @test semantic.status ===
                    :semantic_identity_resolved_source_gauge
                @test semantic.semantic_parameter_identity_resolved
                @test semantic.source_gauge_validated
                @test !semantic.destination_gauge_aligned
                @test !semantic.destination_parameter_vector_ready
                @test !semantic.anchor_candidate_ready
                @test !semantic.convergence_validated
                @test !semantic.numerical_comparison_allowed
                @test !semantic.software_equivalence_claimed
                @test semantic.n_free_parameters == case.expected_free
                @test semantic.n_semantic_rows == case.expected_rows
                @test collect(semantic.rater_values) ≈ case.expected_rater
                @test collect(semantic.item_values) ≈ case.expected_item
                if case.thresholds === :rating_scale
                    @test collect(semantic.threshold_values) ≈
                        case.expected_thresholds
                else
                    @test [collect(values) for values in
                        semantic.threshold_values] ≈ case.expected_thresholds
                end
                @test semantic.identity_checks.design_matrix.n_rows == 36
                @test semantic.identity_checks.design_matrix.
                    n_generalized_items == 12
                @test semantic.identity_checks.design_matrix.
                    exact_header_order_validated
                @test semantic.identity_checks.design_matrix.
                    structural_basis_validated
                @test semantic.identity_checks.design_matrix.
                    predictor_orientation_validated
                @test semantic.identity_checks.reported_version_allowlisted
                @test semantic.identity_checks.design_matrix.
                    max_predictor_identity_residual <= 8eps(Float64)
                @test semantic.identity_checks.constraint_max_abs_residual <=
                    eps(Float64)
                @test all(row -> row.semantic_parameter_identity_resolved,
                    semantic.parameter_rows)
                @test count(row -> row.derivation ===
                    :negative_sum_constraint, semantic.parameter_rows) ==
                    (case.thresholds === :rating_scale ? 3 : 6)
                @test occursin(r"^[0-9a-f]{64}$", semantic.content_hash)
                @test artifact_content_hash(semantic) == semantic.content_hash

                @test_throws ArgumentError load_conquest_semantic_parameters(
                    root,
                    spec;
                    expected_bundle_id = nothing,
                    software_version = "ConQuest 5.47.5",
                    executable_sha256 = repeat("a", 64),
                    executed_at_utc = "2026-07-21T12:56:07Z",
                )
                for unsupported_version in (
                        "ConQuest 5.48.0",
                        "ConQuest 5.47.5.999",
                        "x5.47.5x",
                        "NotConQuest 5.47.5",
                        "5.47.5 x 5.47.5",
                    )
                    @test_throws ArgumentError load_conquest_semantic_parameters(
                        root,
                        spec;
                        expected_bundle_id = bundle.bundle_id,
                        software_version = unsupported_version,
                        executable_sha256 = repeat("a", 64),
                        executed_at_utc = "2026-07-21T12:56:07Z",
                        )
                end
                @test_throws ArgumentError load_conquest_semantic_parameters(
                    root,
                    renamed_spec;
                    expected_bundle_id = bundle.bundle_id,
                    software_version = "ConQuest 5.47.5",
                    executable_sha256 = repeat("a", 64),
                    executed_at_utc = "2026-07-21T12:56:07Z",
                )
            end

            if case.name == "rsm"
                mktempdir() do root
                    save_external_bridge_bundle(root, bundle)
                    _bridge_test_populate_semantic_results(
                        root, bundle, spec, parameters, design_matrix)
                    manifest_path = joinpath(root, "bridge_manifest.json")
                    original_manifest = read(manifest_path, String)
                    bool_dimensions = replace(
                        original_manifest,
                        "\"dimensions\":1" => "\"dimensions\":true";
                        count = 1,
                    )
                    bool_dimensions == original_manifest &&
                        error("semantic fixture dimensions mutation did not apply")
                    rebound_manifest =
                        _bridge_test_rebind_manifest_id(bool_dimensions)
                    _bridge_test_write(manifest_path, rebound_manifest)
                    ledger = string(
                        bytes2hex(sha256(codeunits(rebound_manifest))),
                        "  bridge_manifest.json\r\n",
                    )
                    _bridge_test_write(
                        joinpath(root, "bridge_manifest.sha256"), ledger)
                    validation = validate_external_bridge_bundle(root)
                    @test validation.valid
                    @test_throws ArgumentError load_conquest_semantic_parameters(
                        root,
                        spec;
                        expected_bundle_id = validation.bundle_id,
                        software_version = "ConQuest 5.47.5",
                        executable_sha256 = repeat("a", 64),
                        executed_at_utc = "2026-07-21T12:56:07Z",
                    )
                end
            end

            mktempdir() do root
                save_external_bridge_bundle(root, bundle)
                swapped_comments = replace(
                    parameters,
                    "raterid R000001" => "raterid R000002";
                    count = 1,
                )
                _bridge_test_populate_semantic_results(
                    root, bundle, spec, swapped_comments, design_matrix)
                @test_throws ArgumentError load_conquest_semantic_parameters(
                    root,
                    spec;
                    expected_bundle_id = bundle.bundle_id,
                    software_version = "ConQuest 5.47.5",
                    executable_sha256 = repeat("a", 64),
                    executed_at_utc = "2026-07-21T12:56:07Z",
                )
            end

            mktempdir() do root
                save_external_bridge_bundle(root, bundle)
                swapped_header = replace(
                    design_matrix,
                    "raterid R000001, raterid R000002" =>
                        "raterid R000002, raterid R000001";
                    count = 1,
                )
                swapped_header == design_matrix &&
                    error("semantic fixture header swap did not apply")
                _bridge_test_populate_semantic_results(
                    root, bundle, spec, parameters, swapped_header)
                @test_throws ArgumentError load_conquest_semantic_parameters(
                    root,
                    spec;
                    expected_bundle_id = bundle.bundle_id,
                    software_version = "ConQuest 5.47.5",
                    executable_sha256 = repeat("a", 64),
                    executed_at_utc = "2026-07-21T12:56:07Z",
                )
            end

            mktempdir() do root
                save_external_bridge_bundle(root, bundle)
                reversed_basis = replace(
                    design_matrix,
                    "\n1,2,-1" => "\n1,2,1";
                    count = 1,
                )
                reversed_basis == design_matrix &&
                    error("semantic fixture basis reversal did not apply")
                _bridge_test_populate_semantic_results(
                    root, bundle, spec, parameters, reversed_basis)
                @test_throws ArgumentError load_conquest_semantic_parameters(
                    root,
                    spec;
                    expected_bundle_id = bundle.bundle_id,
                    software_version = "ConQuest 5.47.5",
                    executable_sha256 = repeat("a", 64),
                    executed_at_utc = "2026-07-21T12:56:07Z",
                )
            end
        end
    end

    @testset "ConQuest 5.47.5 macOS known-truth execution fixtures" begin
        fixture_root = joinpath(
            @__DIR__, "fixtures", "conquest_5_47_5")
        fixture_names = Set(readdir(fixture_root))
        @test fixture_names == Set((
            "executed_runner_macos.sh",
            "expectations.json",
            "pcm_control.cqc",
            "pcm_designmatrix.csv",
            "pcm_executed_verifier_macos.sh",
            "pcm_history.tsv",
            "pcm_labels.txt",
            "pcm_manifest.json",
            "pcm_parameters.txt",
            "pcm_receipt.json",
            "rsm_control.cqc",
            "rsm_designmatrix.csv",
            "rsm_executed_verifier_macos.sh",
            "rsm_history.tsv",
            "rsm_labels.txt",
            "rsm_manifest.json",
            "rsm_parameters.txt",
            "rsm_receipt.json",
        ))

        expectations = JSON3.read(read(
            joinpath(fixture_root, "expectations.json"), String))
        @test expectations.schema ==
            "bayesianmgmfrm.conquest_5_47_5_execution_fixture.v1"
        @test expectations.software_version == "5.47.5"
        @test expectations.executed_on.executable_sha256 ==
            "61d0b87f379f1578466b789866366c5cc633d31a6c3501e872861d44ff02da48"
        @test !expectations.privacy.real_person_data_included
        @test !expectations.privacy.row_level_ratings_included
        @test !expectations.privacy.person_estimates_included
        @test !getproperty(expectations.privacy,
            :licence_credentials_or_activation_material_included)
        @test expectations.privacy.licence_metadata_included
        @test expectations.provenance.retained_raw_outputs_per_model == 4
        @test getproperty(expectations.provenance,
            :receipt_output_inventory_records_per_model) == 15
        @test !getproperty(expectations.provenance,
            :unretained_output_bytes_recomputable_from_fixture)
        @test !expectations.provenance.independent_execution_verified
        @test !getproperty(expectations.generation,
            :row_level_generation_reproducible_from_fixture)
        @test expectations.interpretation.scope ==
            "Version-specific known-truth execution evidence; not product equivalence or independent replication."

        for model_name in ("rsm", "pcm")
            expected = getproperty(expectations.models, Symbol(model_name))
            paths = (;
                parameters = joinpath(
                    fixture_root, "$(model_name)_parameters.txt"),
                designmatrix = joinpath(
                    fixture_root, "$(model_name)_designmatrix.csv"),
                history = joinpath(
                    fixture_root, "$(model_name)_history.tsv"),
                labels = joinpath(
                    fixture_root, "$(model_name)_labels.txt"),
                control = joinpath(
                    fixture_root, "$(model_name)_control.cqc"),
                manifest = joinpath(
                    fixture_root, "$(model_name)_manifest.json"),
                receipt = joinpath(
                    fixture_root, "$(model_name)_receipt.json"),
                macos_verifier = joinpath(
                    fixture_root,
                    "$(model_name)_executed_verifier_macos.sh"),
                macos_runner = joinpath(
                    fixture_root, "executed_runner_macos.sh"),
            )
            for role in keys(paths)
                path = getproperty(paths, role)
                @test bytes2hex(sha256(read(path))) ==
                    getproperty(expected.files, role)
            end
            @test filesize(paths.labels) == 0
            @test expected.files.labels == bytes2hex(sha256(UInt8[]))

            manifest_text = read(paths.manifest, String)
            manifest = JSON3.read(manifest_text)
            @test _bridge_test_rebind_manifest_id(manifest_text) ==
                manifest_text
            @test manifest.bundle_id == expected.bundle_id
            @test manifest.software == "conquest"
            @test manifest.data.n_persons == expected.n_persons
            @test manifest.data.n_ratings == expected.n_ratings
            @test manifest.privacy.row_level_ratings_included
            @test !manifest.privacy.original_labels_included
            @test !manifest.execution.performed
            @test manifest.execution.macos_runner_included
            @test length(manifest.expected_outputs) ==
                expected.receipt_output_records
            control_input = only(filter(input ->
                    input.path == "conquest_control.cqc",
                manifest.input_files))
            verifier_input = only(filter(input ->
                    input.path == "verify_bundle_macos.sh",
                manifest.input_files))
            runner_input = only(filter(input ->
                    input.path == "run_conquest_macos.sh",
                manifest.input_files))
            @test control_input.sha256 == expected.files.control
            @test control_input.nbytes == filesize(paths.control)
            @test verifier_input.sha256 == expected.macos_verifier_sha256
            @test verifier_input.nbytes == filesize(paths.macos_verifier)
            @test runner_input.sha256 == expected.macos_runner_sha256
            @test runner_input.nbytes == filesize(paths.macos_runner)
            @test occursin("could not inspect results directory",
                read(paths.macos_verifier, String))
            control_text = read(paths.control, String)
            expected_model = model_name == "rsm" ?
                "model raterid + itemid + step;" :
                "model raterid + itemid + itemid*step;"
            @test occursin(expected_model, control_text)

            receipt = JSON3.read(read(paths.receipt, String))
            @test artifact_content_hash(
                _bridge_test_receipt_payload(receipt)) ==
                receipt.content_hash == expected.receipt_content_hash
            @test receipt.bundle_id == expected.bundle_id
            @test receipt.input_manifest_sha256 == expected.files.manifest
            @test receipt.executable_sha256 ==
                expectations.executed_on.executable_sha256
            @test receipt.executed_at_utc == expected.executed_at_utc
            @test receipt.exit_code == expected.exit_code == 0
            @test receipt.raw_return_integrity_verified
            @test receipt.external_execution_reported_completed
            @test !receipt.external_execution_completed
            @test !receipt.external_execution_independently_verified
            @test !receipt.external_execution_authenticity_verified
            @test !receipt.convergence_validated
            @test !receipt.semantic_parameter_adapter_validated
            @test !receipt.numerical_comparison_allowed
            @test !receipt.software_equivalence_claimed
            @test length(receipt.output_files) ==
                expected.receipt_output_records
            @test Set(String(output.path) for output in receipt.output_files) ==
                Set(String(output.path) for output in manifest.expected_outputs)
            retained_output_paths = (;
                parameters = "results/conquest_parameters.txt",
                designmatrix = "results/conquest_designmatrix.csv",
                history = "results/conquest_history.txt",
                labels = "results/conquest_labels.txt",
            )
            for role in keys(retained_output_paths)
                output_path = getproperty(retained_output_paths, role)
                output = only(filter(row -> row.path == output_path,
                    receipt.output_files))
                fixture_path = getproperty(paths, role)
                @test output.nbytes == filesize(fixture_path)
                @test output.sha256 == getproperty(expected.files, role)
            end
            @test expected.retained_raw_output_files ==
                length(keys(retained_output_paths))

            parameter_rows = load_conquest_parameter_export(
                paths.parameters;
                expected_sha256 = expected.files.parameters,
            )
            @test length(parameter_rows) == expected.n_free_parameters
            @test [row.parameter_number for row in parameter_rows] ==
                collect(1:expected.n_free_parameters)
            @test all(row ->
                    !row.semantic_parameter_identity_resolved &&
                        row.source_comment !== nothing,
                parameter_rows)

            design = _bridge_test_design_matrix(paths.designmatrix)
            design_header = join(design.header, ',')
            @test all(row -> occursin(row.source_comment, design_header),
                parameter_rows)
            @test size(design.matrix) == (36, expected.n_free_parameters)
            @test rank(design.matrix) == expected.n_free_parameters
            @test Set(zip(design.gin, design.category)) ==
                Set((gin, category) for gin in 1:12 for category in 1:3)

            free_values = [row.value for row in parameter_rows]
            rater = vcat(free_values[1:2], -sum(free_values[1:2]))
            item = vcat(free_values[3:5], -sum(free_values[3:5]))
            expected_estimate = expected.estimate_after_constraint_reconstruction
            @test rater ≈ Float64.(expected_estimate.rater) atol = 1e-12
            @test item ≈ Float64.(expected_estimate.item) atol = 1e-12
            @test isapprox(sum(rater), 0.0; atol = 1e-12)
            @test isapprox(sum(item), 0.0; atol = 1e-12)
            @test _bridge_test_rmse(
                rater, Float64.(expected.truth.rater)) ≈
                expected.rmse.rater atol = 1e-14
            @test _bridge_test_rmse(
                item, Float64.(expected.truth.item)) ≈
                expected.rmse.item atol = 1e-14

            if model_name == "rsm"
                steps = [free_values[6], -free_values[6]]
                @test steps ≈ Float64.(expected_estimate.step) atol = 1e-12
                @test _bridge_test_rmse(
                    steps, Float64.(expected.truth.step)) ≈
                    expected.rmse.step atol = 1e-14
            else
                item_steps = [[value, -value] for value in free_values[6:9]]
                expected_steps = [Float64.(step)
                    for step in expected_estimate.item_steps]
                truth_steps = [Float64.(step)
                    for step in expected.truth.item_steps]
                @test item_steps ≈ expected_steps atol = 1e-12
                @test all(step -> isapprox(sum(step), 0.0; atol = 1e-12),
                    item_steps)
                @test _bridge_test_rmse(
                    reduce(vcat, item_steps), reduce(vcat, truth_steps)) ≈
                    expected.rmse.step atol = 1e-14
            end

            history = _bridge_test_history(paths.history)
            selected_index = argmin(history.deviance)
            @test history.iteration[selected_index] ==
                expected.selected_iteration
            @test last(history.iteration) == expected.history_last_iteration
            @test history.deviance[selected_index] ≈
                expected.selected_deviance atol = 1e-10
            @test history.population_variance[selected_index] ≈
                expected.selected_population_variance atol = 1e-10
            selected_free_values = parse.(Float64,
                history.raw[selected_index][6:(5 + expected.n_free_parameters)])
            @test selected_free_values ≈ free_values atol = 1e-12
            @test selected_index != length(history.iteration)
        end
    end

    @testset "synthetic raw-return receipts" begin
        conquest = conquest_bridge_bundle(pcm; title = "Returned ConQuest PCM")
        mktempdir() do root
            save_external_bridge_bundle(root, conquest)
            _bridge_test_populate_results(root, conquest)
            _bridge_test_write(
                joinpath(root, "results", "conquest_labels.txt"), "")
            large_cases = repeat("case,row,without,retained,bytes\n", 9000)
            large_report = repeat("parameter report row\n", 9000)
            _bridge_test_write(
                joinpath(root, "results", "conquest_cases_wle.csv"),
                large_cases,
            )
            _bridge_test_write(
                joinpath(root, "results", "conquest_show_parameters.txt"),
                large_report,
            )
            receipt = external_bridge_result_receipt(
                root;
                expected_bundle_id = conquest.bundle_id,
                software_version = "ConQuest synthetic licensed-host report",
                executable_sha256 = repeat("a", 64),
                executed_at_utc = "2026-07-21T12:00:00Z",
            )
            @test receipt.status === :raw_return_integrity_verified
            @test receipt.raw_return_integrity_verified
            @test !receipt.external_execution_completed
            @test receipt.external_execution_reported_completed
            @test !receipt.external_execution_independently_verified
            @test !receipt.external_execution_authenticity_verified
            @test !receipt.convergence_validated
            @test !receipt.semantic_parameter_adapter_validated
            @test !receipt.numerical_comparison_allowed
            @test receipt.parameter_export.parsed
            @test receipt.parameter_export.n_parameter_pairs == 2
            labels_output = only(filter(
                output -> output.role === :conquest_labels,
                receipt.output_files,
            ))
            @test labels_output.nbytes == 0
            @test labels_output.sha256 == bytes2hex(sha256(UInt8[]))
            parameter_output = only(filter(
                output -> output.path == "results/conquest_parameters.txt",
                receipt.output_files,
            ))
            @test receipt.parameter_export.source_sha256 == parameter_output.sha256
            case_output = only(filter(
                output -> output.path == "results/conquest_cases_wle.csv",
                receipt.output_files,
            ))
            @test case_output.nbytes == ncodeunits(large_cases)
            @test case_output.sha256 == bytes2hex(sha256(codeunits(large_cases)))

            validation = validate_external_bridge_bundle(
                root; expected_bundle_id = conquest.bundle_id)
            snapshots = BayesianMGMFRM._external_bridge_result_snapshots(
                root, validation.expected_outputs, validation.software)
            @test all(snapshot ->
                    snapshot.role === :process_exit_code ||
                        snapshot.content === nothing,
                snapshots)
            parameter_snapshot = only(filter(
                snapshot -> snapshot.role === :parameter_pairs,
                snapshots,
            ))
            @test parameter_snapshot.content === nothing
            @test parameter_snapshot.parameter_export.n_parameter_pairs == 2

            estimation_path = joinpath(
                root, "results", "conquest_estimation.log")
            _bridge_test_write(estimation_path, "")
            @test_throws ArgumentError external_bridge_result_receipt(
                root;
                expected_bundle_id = conquest.bundle_id,
                software_version = "ConQuest synthetic licensed-host report",
                executable_sha256 = repeat("a", 64),
                executed_at_utc = "2026-07-21T12:00:00Z",
            )
            _bridge_test_write(estimation_path, "completed\n")

            unexpected = _bridge_test_write(
                joinpath(root, "results", "undeclared.txt"), "unexpected\n")
            @test_throws ArgumentError external_bridge_result_receipt(
                root;
                expected_bundle_id = conquest.bundle_id,
                software_version = "ConQuest synthetic licensed-host report",
                executable_sha256 = repeat("a", 64),
                executed_at_utc = "2026-07-21T12:00:00Z",
            )
            rm(unexpected)

            root_note = _bridge_test_write(
                joinpath(root, "operator_notes.txt"), "recorded elsewhere\n")
            @test_throws ArgumentError external_bridge_result_receipt(
                root;
                expected_bundle_id = conquest.bundle_id,
                software_version = "ConQuest synthetic licensed-host report",
                executable_sha256 = repeat("a", 64),
                executed_at_utc = "2026-07-21T12:00:00Z",
            )
            rm(root_note)

            undeclared_directory = joinpath(root, "results", "undeclared")
            mkpath(undeclared_directory)
            @test_throws ArgumentError external_bridge_result_receipt(
                root;
                expected_bundle_id = conquest.bundle_id,
                software_version = "ConQuest synthetic licensed-host report",
                executable_sha256 = repeat("a", 64),
                executed_at_utc = "2026-07-21T12:00:00Z",
            )
            rm(undeclared_directory; recursive = true)

            execution_lock = joinpath(root, ".bridge_execution.lock")
            mkpath(execution_lock)
            @test_throws ArgumentError external_bridge_result_receipt(
                root;
                expected_bundle_id = conquest.bundle_id,
                software_version = "ConQuest synthetic licensed-host report",
                executable_sha256 = repeat("a", 64),
                executed_at_utc = "2026-07-21T12:00:00Z",
            )
            rm(execution_lock; recursive = true)

            _bridge_test_write(
                joinpath(root, "results", "conquest_estimation.log"),
                string(
                    repeat("x", BayesianMGMFRM._EXTERNAL_BRIDGE_STREAM_CHUNK_BYTES - 3),
                    "FaTaL\tERROR\n",
                ),
            )
            @test_throws ArgumentError external_bridge_result_receipt(
                root;
                expected_bundle_id = conquest.bundle_id,
                software_version = "ConQuest synthetic licensed-host report",
                executable_sha256 = repeat("a", 64),
                executed_at_utc = "2026-07-21T12:00:00Z",
            )
        end

        facets = facets_bridge_bundle(rsm; title = "Returned FACETS RSM")
        mktempdir() do root
            save_external_bridge_bundle(root, facets)
            _bridge_test_populate_results(root, facets)
            receipt = external_bridge_result_receipt(
                root;
                expected_bundle_id = facets.bundle_id,
                software_version = "FACETS synthetic licensed-host report",
                executable_sha256 = repeat("b", 64),
                executed_at_utc = "2026-07-21T12:00:00Z",
            )
            @test receipt.software === :facets
            @test !receipt.external_execution_completed
            @test receipt.external_execution_reported_completed
            @test receipt.parameter_export.parsed == false
            @test receipt.parameter_export.reason ===
                :facets_output_format_not_yet_validated
            @test receipt.raw_return_integrity_verified
            @test length(receipt.output_files) ==
                length(facets.manifest.expected_outputs)

            _bridge_test_write(
                joinpath(root, "results", "external_exit_code.txt"), "7\n")
            @test_throws ArgumentError external_bridge_result_receipt(
                root;
                expected_bundle_id = facets.bundle_id,
                software_version = "FACETS synthetic licensed-host report",
                executable_sha256 = repeat("b", 64),
                executed_at_utc = "2026-07-21T12:00:00Z",
            )
        end
    end
end
