using Test
using SHA

const REPOSITORY_ROOT = normpath(joinpath(@__DIR__, ".."))
include(joinpath(
    REPOSITORY_ROOT,
    "scripts",
    "local_dependence_pilot_attempt_archive.jl",
))
using .LocalDependencePilotAttemptArchive
const Archive = LocalDependencePilotAttemptArchive

hex64(character::AbstractString) = repeat(character, 64)

function write_archive_json(path::AbstractString, value)
    mkpath(dirname(path))
    open(path, "w") do io
        Archive.write_json(io, value)
        println(io)
    end
    return path
end

function rehash_archive_artifact(artifact::NamedTuple; replacements...)
    names = Tuple(name for name in propertynames(artifact)
        if name !== :content_hash)
    material = NamedTuple{names}(Tuple(
        getproperty(artifact, name) for name in names))
    return Archive.ld1b_archive_with_content_hash(
        merge(material, (; replacements...)))
end

function test_plan_identity()
    return (;
        plan_id = hex64("1"),
        protocol_plan_id = hex64("2"),
        protocol_file_sha256 = hex64("3"),
        protocol_content_hash = hex64("4"),
        ordered_job_rows_sha256 = hex64("5"),
        pilot_contract_sha256 = hex64("6"),
        release_scope = :local_dependence_ld1b_pilot,
    )
end

function test_execution_source_identity()
    local_json_path = joinpath(REPOSITORY_ROOT, "scripts", "local_json.jl")
    return (;
        batch_runner_source_sha256 = hex64("a"),
        local_json_source_sha256 = bytes2hex(open(sha256, local_json_path)),
        job_runner_source_sha256 = hex64("b"),
        attempt_archive_source_sha256 =
            Archive.ld1b_attempt_archive_source_sha256(),
        job_core_source_sha256 = hex64("c"),
    )
end

function test_job_identity()
    return (;
        job_id = "ld1b1_pilot__rep01__s05__null_support_at_minimum",
        row_index = 5,
        scenario_index = 5,
        scenario_id = :null_support_at_minimum,
        replication = 1,
        expected_action = :fit_and_score_diagnostic,
        seed = 410_005,
        fit_seed = 510_005,
    )
end

function test_result(plan, execution, job;
        attempt_number::Int = 1,
        attempt_role::Symbol = :primary,
        execution_context = Archive.ld1b_execution_context(),
        terminal_status::Symbol = :completed,
        terminal_outcome_code::Symbol = :completed)
    context = Archive.ld1b_validate_execution_context(execution_context)
    attempt = Archive._ld1b_attempt_identity(
        attempt_number,
        attempt_role;
        execution_context = context,
    )
    material = (;
        schema = "bayesianmgmfrm.test_local_dependence_job_result.v1",
        execution_context = context,
        plan_identity = plan,
        execution_source_identity = execution,
        job,
        attempt,
        terminal_status,
        terminal_outcome_code,
        diagnostic_payload = (;
            local_dependence_fit_was_run = false,
            test_fixture_only = true,
        ),
    )
    return Archive.ld1b_archive_with_content_hash(material)
end

function completed_fixture(root::AbstractString;
        attempt_name::AbstractString = "attempt_001",
        attempt_number::Int = 1,
        attempt_role::Symbol = :primary,
        execution_context = Archive.ld1b_execution_context(),
        terminal_status::Symbol = :completed,
        terminal_outcome_code::Symbol = :completed)
    plan = test_plan_identity()
    execution = test_execution_source_identity()
    job = test_job_identity()
    attempt_dir = joinpath(root, attempt_name)
    mkpath(joinpath(attempt_dir, "evidence"))
    write_archive_json(
        joinpath(attempt_dir, "evidence", "generated_data_source.json"),
        (schema = "test.generated_data_source.v1", seed = 410_005),
    )
    evidence_path = write_archive_json(
        joinpath(attempt_dir, "evidence", "generated_data_evidence.json"),
        (schema = "test.generated_data_evidence.v1", complete = true),
    )
    result = test_result(plan, execution, job;
        attempt_number,
        attempt_role,
        execution_context,
        terminal_status,
        terminal_outcome_code,
    )
    result_path = write_archive_json(
        joinpath(attempt_dir, "job_result.json"),
        result,
    )
    return (;
        root,
        attempt_dir,
        staging_dir = joinpath(root, ".publication_staging"),
        plan,
        execution,
        job,
        attempt_number,
        attempt_role,
        execution_context = Archive.ld1b_validate_execution_context(
            execution_context),
        terminal_status,
        terminal_outcome_code,
        evidence_path,
        evidence_manifest_sha256 = bytes2hex(open(sha256, evidence_path)),
        result_path,
        result,
    )
end

function publish_completed(fixture)
    return Archive.ld1b_publish_completed_attempt_seal(
        fixture.attempt_dir;
        plan_identity = fixture.plan,
        execution_source_identity = fixture.execution,
        job_identity = fixture.job,
        attempt_number = fixture.attempt_number,
        attempt_role = fixture.attempt_role,
        execution_context = fixture.execution_context,
        terminal_status = fixture.terminal_status,
        terminal_outcome_code = fixture.terminal_outcome_code,
        evidence_manifest_sha256 = fixture.evidence_manifest_sha256,
        staging_dir = fixture.staging_dir,
        boundary = fixture.root,
    )
end

function validate_completed(fixture; kwargs...)
    arguments = merge((;
        plan_identity = fixture.plan,
        execution_source_identity = fixture.execution,
        job_identity = fixture.job,
        attempt_number = fixture.attempt_number,
        attempt_role = fixture.attempt_role,
        execution_context = fixture.execution_context,
        terminal_status = fixture.terminal_status,
        terminal_outcome_code = fixture.terminal_outcome_code,
    ), (; kwargs...))
    return Archive.ld1b_validate_completed_attempt_seal(
        fixture.attempt_dir; arguments...)
end

function retirement_fixture(root::AbstractString;
        attempt_name::AbstractString = "attempt_001",
        attempt_number::Int = 1,
        attempt_role::Symbol = :primary)
    attempt_dir = joinpath(root, attempt_name)
    mkpath(joinpath(attempt_dir, "partial"))
    partial_path = write_archive_json(
        joinpath(attempt_dir, "partial", "interrupted_state.json"),
        (schema = "test.interrupted_state.v1", completed_draws = 17),
    )
    return (;
        root,
        attempt_dir,
        staging_dir = joinpath(root, ".publication_staging"),
        plan = test_plan_identity(),
        execution = test_execution_source_identity(),
        job = test_job_identity(),
        attempt_number,
        attempt_role,
        reason = :operator_confirmed_interruption,
        review_sha256 = hex64("d"),
        partial_path,
    )
end

function publish_retirement(fixture)
    return Archive.ld1b_publish_attempt_retirement_marker(
        fixture.attempt_dir;
        plan_identity = fixture.plan,
        execution_source_identity = fixture.execution,
        job_identity = fixture.job,
        attempt_number = fixture.attempt_number,
        attempt_role = fixture.attempt_role,
        retirement_reason_code = fixture.reason,
        review_record_sha256 = fixture.review_sha256,
        process_confirmed_stopped = true,
        staging_dir = fixture.staging_dir,
        boundary = fixture.root,
    )
end

function validate_retirement(fixture; kwargs...)
    arguments = merge((;
        plan_identity = fixture.plan,
        execution_source_identity = fixture.execution,
        job_identity = fixture.job,
        attempt_number = fixture.attempt_number,
        attempt_role = fixture.attempt_role,
        expected_reason_code = fixture.reason,
        expected_review_record_sha256 = fixture.review_sha256,
    ), (; kwargs...))
    return Archive.ld1b_validate_attempt_retirement_marker(
        fixture.attempt_dir; arguments...)
end

@testset "local-dependence pilot attempt archive" begin
    @testset "canonical content hash" begin
        artifact = Archive.ld1b_archive_with_content_hash((;
            schema = "test.archive.v1",
            purpose = :unit_test,
            values = (3, 1, 2),
        ))
        digest = Archive.ld1b_verify_archive_content_hash(artifact)
        @test digest == artifact.content_hash.value
        @test digest == Archive.ld1b_archive_canonical_sha256((;
            schema = "test.archive.v1",
            purpose = :unit_test,
            values = (3, 1, 2),
        ))
        @test_throws Exception Archive.ld1b_archive_with_content_hash(artifact)
        tampered = merge(artifact, (; purpose = :changed))
        @test_throws Exception Archive.ld1b_verify_archive_content_hash(tampered)
    end

    @testset "execution context and attempt identity" begin
        pilot = Archive.ld1b_execution_context(:pilot)
        bounded_smoke = Archive.ld1b_execution_context(:bounded_smoke)
        @test pilot == (;
            execution_scope = :pilot,
            root_namespace = :local_dependence_pilot,
            official_pilot_denominator_eligible = true,
        )
        @test bounded_smoke == (;
            execution_scope = :bounded_smoke,
            root_namespace = :local_dependence_pilot_bounded_smoke_v1,
            official_pilot_denominator_eligible = false,
        )
        @test Archive.ld1b_validate_execution_context(:pilot) == pilot
        @test Archive.ld1b_validate_execution_context(
            bounded_smoke;
            expected_scope = :bounded_smoke,
        ) == bounded_smoke
        @test_throws Exception Archive.ld1b_execution_context(:unsupported)
        @test_throws Exception Archive.ld1b_validate_execution_context(
            merge(pilot, (; unexpected = true)))
        @test_throws Exception Archive.ld1b_validate_execution_context(
            merge(pilot, (; root_namespace = :wrong_namespace)))
        @test_throws Exception Archive.ld1b_validate_execution_context(
            merge(bounded_smoke, (;
                official_pilot_denominator_eligible = true,
            )))
        @test_throws Exception Archive.ld1b_validate_execution_context(
            pilot;
            expected_scope = :bounded_smoke,
        )

        @test Archive._ld1b_attempt_identity(
            1,
            :primary;
            execution_context = pilot,
        ) == (;
            number = 1,
            role = :primary,
            counts_toward_primary = true,
        )
        @test Archive._ld1b_attempt_identity(
            2,
            :remediation;
            execution_context = pilot,
        ).counts_toward_primary === false
        @test Archive._ld1b_attempt_identity(
            1,
            :verification;
            execution_context = bounded_smoke,
        ) == (;
            number = 1,
            role = :verification,
            counts_toward_primary = false,
        )
        @test_throws Exception Archive._ld1b_attempt_identity(
            1,
            :verification;
            execution_context = pilot,
        )
        @test_throws Exception Archive._ld1b_attempt_identity(
            1,
            :primary;
            execution_context = bounded_smoke,
        )
        @test_throws Exception Archive._ld1b_attempt_identity(
            2,
            :verification;
            execution_context = bounded_smoke,
        )
    end

    @testset "deterministic inventory and link rejection" begin
        mktempdir() do root
            attempt_dir = joinpath(root, "attempt")
            mkpath(joinpath(attempt_dir, "z"))
            write(joinpath(attempt_dir, "b.txt"), "bravo")
            write(joinpath(attempt_dir, "a.txt"), "alpha")
            write(joinpath(attempt_dir, "z", "c.txt"), "charlie")
            write(joinpath(
                attempt_dir,
                Archive.LD1B_ATTEMPT_SEAL_FILENAME,
            ), "excluded")
            write(joinpath(
                attempt_dir,
                Archive.LD1B_ATTEMPT_RETIREMENT_FILENAME,
            ), "excluded")
            first = Archive.ld1b_attempt_inventory(attempt_dir)
            second = Archive.ld1b_attempt_inventory(attempt_dir)
            @test first == second
            @test [row.path for row in first] ==
                ["a.txt", "b.txt", "z", "z/c.txt"]
            @test all(row -> !(row.path in (
                Archive.LD1B_ATTEMPT_SEAL_FILENAME,
                Archive.LD1B_ATTEMPT_RETIREMENT_FILENAME,
            )), first)
            @test Archive.ld1b_attempt_inventory_sha256(attempt_dir) ==
                Archive.ld1b_archive_canonical_sha256(first)
        end

        mktempdir() do root
            attempt_dir = joinpath(root, "attempt")
            mkpath(attempt_dir)
            source = joinpath(attempt_dir, "payload.json")
            write(source, "{}")
            hardlink(source, joinpath(root, "second_link.json"))
            @test_throws Exception Archive.ld1b_attempt_inventory(attempt_dir)
        end

        mktempdir() do root
            attempt_dir = joinpath(root, "attempt")
            mkpath(attempt_dir)
            write(joinpath(root, "outside.json"), "{}")
            symlink(
                joinpath(root, "outside.json"),
                joinpath(attempt_dir, "payload.json"),
            )
            @test_throws Exception Archive.ld1b_attempt_inventory(attempt_dir)
        end
    end

    @testset "same-volume CREATE_NEW publication" begin
        mktempdir() do root
            target_parent = joinpath(root, "attempt")
            mkpath(target_parent)
            target = joinpath(target_parent, "marker.json")
            staging = joinpath(root, "staging")
            artifact = Archive.ld1b_archive_with_content_hash((;
                schema = "test.publication.v1",
                sequence = 1,
            ))
            validator = value -> begin
                Archive.ld1b_verify_archive_content_hash(value)
                value["schema"] == "test.publication.v1" ||
                    error("wrong schema")
                return true
            end
            published = Archive.ld1b_atomic_publish_json_create_new(
                target,
                artifact,
                staging,
                root;
                semantic_validator = validator,
                artifact_label = "test marker",
            )
            @test published.publication ===
                :same_volume_hardlink_create_new
            @test published.overwrite_allowed === false
            @test published.published === true
            @test stat(target).nlink == 1
            @test_throws Exception Archive.ld1b_atomic_publish_json_create_new(
                target,
                artifact,
                staging,
                root;
                semantic_validator = validator,
            )
        end

        mktempdir() do root
            target_parent = joinpath(root, "attempt")
            mkpath(target_parent)
            staging = joinpath(root, "staging")
            artifact = Archive.ld1b_archive_with_content_hash((value = 1,))
            existing_directory = joinpath(target_parent, "occupied")
            mkpath(existing_directory)
            @test_throws Exception Archive.ld1b_atomic_publish_json_create_new(
                existing_directory,
                artifact,
                staging,
                root;
                semantic_validator =
                    Archive.ld1b_verify_archive_content_hash,
            )
            dangling = joinpath(target_parent, "dangling.json")
            symlink("missing.json", dangling)
            @test_throws Exception Archive.ld1b_atomic_publish_json_create_new(
                dangling,
                artifact,
                staging,
                root;
                semantic_validator =
                    Archive.ld1b_verify_archive_content_hash,
            )
        end

        mktempdir() do root
            target_parent = joinpath(root, "attempt")
            mkpath(target_parent)
            target = joinpath(target_parent, "race.json")
            staging = joinpath(root, "staging")
            artifacts = [
                Archive.ld1b_archive_with_content_hash((winner = index,))
                for index in 1:2
            ]
            tasks = [
                Threads.@spawn try
                    Archive.ld1b_atomic_publish_json_create_new(
                        target,
                        artifact,
                        staging,
                        root;
                        semantic_validator =
                            Archive.ld1b_verify_archive_content_hash,
                    )
                    true
                catch
                    false
                end
                for artifact in artifacts
            ]
            outcomes = fetch.(tasks)
            @test count(identity, outcomes) == 1
            @test isfile(target)
            @test stat(target).nlink == 1
        end

        mktempdir() do root
            target_parent = joinpath(root, "attempt")
            mkpath(target_parent)
            target = joinpath(target_parent, "invalid.json")
            artifact = Archive.ld1b_archive_with_content_hash((value = 1,))
            @test_throws Exception Archive.ld1b_atomic_publish_json_create_new(
                target,
                artifact,
                joinpath(root, "staging"),
                root;
                semantic_validator = _ -> error("semantic rejection"),
            )
            @test !ispath(target)
            @test !islink(target)
        end


        @testset "deterministic publication fault windows" begin
            artifact = Archive.ld1b_archive_with_content_hash((;
                schema = "test.publication_fault.v1",
                sequence = 1,
            ))
            validator = value -> begin
                Archive.ld1b_verify_archive_content_hash(value)
                value["schema"] == "test.publication_fault.v1" ||
                    error("wrong schema")
                return true
            end

            mktempdir() do root
                target_parent = joinpath(root, "attempt")
                mkpath(target_parent)
                target = joinpath(target_parent, "pre_link.json")
                staging = joinpath(root, "staging")
                @test_throws Exception Archive.
                    ld1b_atomic_publish_json_create_new(
                        target,
                        artifact,
                        staging,
                        root;
                        semantic_validator = validator,
                        _fault_injection_stage = :pre_link,
                    )
                @test !ispath(target)
                @test length(readdir(staging)) == 1
                orphan = only(readdir(staging; join = true))
                @test stat(orphan).nlink == 1

                publication = Archive.ld1b_atomic_publish_json_create_new(
                    target,
                    artifact,
                    staging,
                    root;
                    semantic_validator = validator,
                )
                @test publication.published
                @test stat(target).nlink == 1
                @test isfile(orphan)
            end

            mktempdir() do root
                target_parent = joinpath(root, "attempt")
                mkpath(target_parent)
                target = joinpath(target_parent, "post_link.json")
                staging = joinpath(root, "staging")
                @test_throws Exception Archive.
                    ld1b_atomic_publish_json_create_new(
                        target,
                        artifact,
                        staging,
                        root;
                        semantic_validator = validator,
                        _fault_injection_stage = :post_link_pre_unlink,
                    )
                @test isfile(target)
                @test stat(target).nlink == 2
                alias = only(readdir(staging; join = true))
                @test stat(alias).device == stat(target).device
                @test stat(alias).inode == stat(target).inode
                @test_throws Exception Archive._ld1b_read_json_snapshot(
                    target, root, "ambiguous published target")

                reconciliation =
                    Archive.ld1b_reconcile_json_create_new_staging_alias(
                        target,
                        artifact,
                        staging,
                        root;
                        semantic_validator = validator,
                    )
                @test reconciliation.reconciled
                @test reconciliation.staging_alias_removed
                @test stat(target).nlink == 1
                @test isempty(readdir(staging))
                @test Archive._ld1b_read_json_snapshot(
                    target, root, "reconciled target").sha256 ==
                    reconciliation.file_sha256
            end

            mktempdir() do root
                target_parent = joinpath(root, "attempt")
                mkpath(target_parent)
                target = joinpath(target_parent, "post_unlink.json")
                staging = joinpath(root, "staging")
                @test_throws Exception Archive.
                    ld1b_atomic_publish_json_create_new(
                        target,
                        artifact,
                        staging,
                        root;
                        semantic_validator = validator,
                        _fault_injection_stage =
                            :post_unlink_pre_validation,
                    )
                @test isfile(target)
                @test stat(target).nlink == 1
                @test isempty(readdir(staging))
                snapshot = Archive._ld1b_read_json_snapshot(
                    target, root, "post-unlink target")
                @test snapshot.bytes == Archive._ld1b_encode_json_bytes(artifact)
                @test validator(snapshot.parsed)
            end

            mktempdir() do root
                target_parent = joinpath(root, "attempt")
                mkpath(target_parent)
                target = joinpath(target_parent, "ambiguous.json")
                staging = joinpath(root, "staging")
                @test_throws Exception Archive.
                    ld1b_atomic_publish_json_create_new(
                        target,
                        artifact,
                        staging,
                        root;
                        semantic_validator = validator,
                        _fault_injection_stage = :post_link_pre_unlink,
                    )
                first_alias = only(readdir(staging; join = true))
                second_alias = joinpath(staging, "second_alias.json")
                hardlink(first_alias, second_alias)
                @test stat(target).nlink == 3
                @test_throws Exception Archive.
                    ld1b_reconcile_json_create_new_staging_alias(
                        target,
                        artifact,
                        staging,
                        root;
                        semantic_validator = validator,
                    )
                @test stat(target).nlink == 3
                @test isfile(first_alias)
                @test isfile(second_alias)
            end

            mktempdir() do root
                target_parent = joinpath(root, "attempt")
                mkpath(target_parent)
                target = joinpath(target_parent, "wrong_bytes.json")
                staging = joinpath(root, "staging")
                @test_throws Exception Archive.
                    ld1b_atomic_publish_json_create_new(
                        target,
                        artifact,
                        staging,
                        root;
                        semantic_validator = validator,
                        _fault_injection_stage = :post_link_pre_unlink,
                    )
                wrong_artifact = Archive.ld1b_archive_with_content_hash((;
                    schema = "test.publication_fault.v1",
                    sequence = 2,
                ))
                @test_throws Exception Archive.
                    ld1b_reconcile_json_create_new_staging_alias(
                        target,
                        wrong_artifact,
                        staging,
                        root;
                        semantic_validator = validator,
                    )
                @test stat(target).nlink == 2
                @test length(readdir(staging)) == 1
            end
        end
    end

    @testset "completed-attempt seal" begin
        mktempdir() do root
            fixture = completed_fixture(root)
            result_sha256 = bytes2hex(open(sha256, fixture.result_path))
            publication = publish_completed(fixture)
            validation = publication.validation
            @test validation.valid
            @test validation.state === :sealed_terminal
            @test validation.terminal_status === :completed
            @test validation.terminal_outcome_code === :completed
            @test validation.execution_context ==
                Archive.ld1b_execution_context(:pilot)
            @test validation.counts_toward_primary === true
            @test validation.result_file_sha256 == result_sha256
            @test validation.result_content_hash ==
                fixture.result.content_hash.value
            @test validation.evidence_manifest_sha256 ==
                fixture.evidence_manifest_sha256
            @test publication.publication.publication ===
                :same_volume_hardlink_create_new
            @test publication.artifact.schema ==
                Archive.LD1B_ATTEMPT_SEAL_SCHEMA
            @test publication.artifact.execution_context ==
                Archive.ld1b_execution_context(:pilot)
            @test publication.artifact.attempt == (;
                number = 1,
                role = :primary,
                counts_toward_primary = true,
            )
            @test publication.artifact.contract.execution_context_bound
            @test publication.artifact.contract.
                execution_root_namespace_bound
            @test stat(joinpath(
                fixture.attempt_dir,
                Archive.LD1B_ATTEMPT_SEAL_FILENAME,
            )).nlink == 1
            @test_throws Exception publish_completed(fixture)
            @test_throws Exception validate_completed(
                fixture;
                terminal_status = :failed,
            )
            @test_throws Exception validate_completed(
                fixture;
                plan_identity =
                    merge(fixture.plan, (; plan_id = hex64("9"))),
            )
        end

        mktempdir() do root
            bounded_smoke = Archive.ld1b_execution_context(:bounded_smoke)
            fixture = completed_fixture(
                root;
                attempt_role = :verification,
                execution_context = bounded_smoke,
            )
            publication = publish_completed(fixture)
            validation = publication.validation
            @test validation.valid
            @test validation.execution_context == bounded_smoke
            @test validation.execution_context.root_namespace ===
                :local_dependence_pilot_bounded_smoke_v1
            @test validation.execution_context.
                official_pilot_denominator_eligible === false
            @test validation.counts_toward_primary === false
            @test publication.artifact.execution_context == bounded_smoke
            @test publication.artifact.attempt == (;
                number = 1,
                role = :verification,
                counts_toward_primary = false,
            )
            @test_throws Exception validate_completed(
                fixture;
                execution_context = Archive.ld1b_execution_context(:pilot),
                attempt_role = :primary,
            )
        end

        mktempdir() do root
            fixture = completed_fixture(root)
            publish_completed(fixture)
            open(fixture.result_path, "a") do io
                write(io, " ")
            end
            @test_throws Exception validate_completed(fixture)
        end

        mktempdir() do root
            fixture = completed_fixture(root)
            publish_completed(fixture)
            write(joinpath(fixture.attempt_dir, "postseal.txt"), "forbidden")
            @test_throws Exception validate_completed(fixture)
        end

        mktempdir() do root
            fixture = completed_fixture(root)
            publish_completed(fixture)
            write(joinpath(
                fixture.attempt_dir,
                Archive.LD1B_ATTEMPT_RETIREMENT_FILENAME,
            ), "{}")
            @test_throws Exception validate_completed(fixture)
        end

        mktempdir() do root
            fixture = completed_fixture(root)
            publish_completed(fixture)
            seal_path = joinpath(
                fixture.attempt_dir,
                Archive.LD1B_ATTEMPT_SEAL_FILENAME,
            )
            hardlink(seal_path, joinpath(root, "second_seal_link.json"))
            @test_throws Exception validate_completed(fixture)
        end

        mktempdir() do root
            fixture = completed_fixture(root)
            write(joinpath(
                fixture.attempt_dir,
                Archive.LD1B_ATTEMPT_RETIREMENT_FILENAME,
            ), "{}")
            @test_throws Exception Archive.ld1b_completed_attempt_seal(
                fixture.attempt_dir;
                plan_identity = fixture.plan,
                execution_source_identity = fixture.execution,
                job_identity = fixture.job,
                attempt_number = fixture.attempt_number,
                attempt_role = fixture.attempt_role,
                terminal_status = fixture.terminal_status,
                terminal_outcome_code = fixture.terminal_outcome_code,
                evidence_manifest_sha256 =
                    fixture.evidence_manifest_sha256,
            )
        end

        mktempdir() do root
            fixture = completed_fixture(root)
            tampered = merge(fixture.result, (; diagnostic_payload = (;
                local_dependence_fit_was_run = true,
                test_fixture_only = false,
            )))
            write_archive_json(fixture.result_path, tampered)
            @test_throws Exception Archive.ld1b_completed_attempt_seal(
                fixture.attempt_dir;
                plan_identity = fixture.plan,
                execution_source_identity = fixture.execution,
                job_identity = fixture.job,
                attempt_number = fixture.attempt_number,
                attempt_role = fixture.attempt_role,
                terminal_status = fixture.terminal_status,
                terminal_outcome_code = fixture.terminal_outcome_code,
                evidence_manifest_sha256 =
                    fixture.evidence_manifest_sha256,
            )
        end

        mktempdir() do root
            bounded_smoke = Archive.ld1b_execution_context(:bounded_smoke)
            fixture = completed_fixture(
                root;
                attempt_role = :verification,
                execution_context = bounded_smoke,
            )
            wrong_context = rehash_archive_artifact(
                fixture.result;
                execution_context = Archive.ld1b_execution_context(:pilot),
            )
            write_archive_json(fixture.result_path, wrong_context)
            @test_throws Exception Archive.ld1b_completed_attempt_seal(
                fixture.attempt_dir;
                plan_identity = fixture.plan,
                execution_source_identity = fixture.execution,
                job_identity = fixture.job,
                attempt_number = fixture.attempt_number,
                attempt_role = fixture.attempt_role,
                execution_context = fixture.execution_context,
                terminal_status = fixture.terminal_status,
                terminal_outcome_code = fixture.terminal_outcome_code,
                evidence_manifest_sha256 =
                    fixture.evidence_manifest_sha256,
            )
        end

        mktempdir() do root
            bounded_smoke = Archive.ld1b_execution_context(:bounded_smoke)
            fixture = completed_fixture(
                root;
                attempt_role = :verification,
                execution_context = bounded_smoke,
            )
            wrong_contribution = rehash_archive_artifact(
                fixture.result;
                attempt = merge(fixture.result.attempt, (;
                    counts_toward_primary = true,
                )),
            )
            write_archive_json(fixture.result_path, wrong_contribution)
            @test_throws Exception Archive.ld1b_completed_attempt_seal(
                fixture.attempt_dir;
                plan_identity = fixture.plan,
                execution_source_identity = fixture.execution,
                job_identity = fixture.job,
                attempt_number = fixture.attempt_number,
                attempt_role = fixture.attempt_role,
                execution_context = fixture.execution_context,
                terminal_status = fixture.terminal_status,
                terminal_outcome_code = fixture.terminal_outcome_code,
                evidence_manifest_sha256 =
                    fixture.evidence_manifest_sha256,
            )
        end

        mktempdir() do root
            bounded_smoke = Archive.ld1b_execution_context(:bounded_smoke)
            fixture = completed_fixture(
                root;
                attempt_role = :verification,
                execution_context = bounded_smoke,
            )
            artifact = Archive.ld1b_completed_attempt_seal(
                fixture.attempt_dir;
                plan_identity = fixture.plan,
                execution_source_identity = fixture.execution,
                job_identity = fixture.job,
                attempt_number = fixture.attempt_number,
                attempt_role = fixture.attempt_role,
                execution_context = fixture.execution_context,
                terminal_status = fixture.terminal_status,
                terminal_outcome_code = fixture.terminal_outcome_code,
                evidence_manifest_sha256 =
                    fixture.evidence_manifest_sha256,
            )
            wrong_context = rehash_archive_artifact(
                artifact;
                execution_context = Archive.ld1b_execution_context(:pilot),
            )
            write_archive_json(
                joinpath(
                    fixture.attempt_dir,
                    Archive.LD1B_ATTEMPT_SEAL_FILENAME,
                ),
                wrong_context,
            )
            @test_throws Exception validate_completed(fixture)
        end

        mktempdir() do root
            fixture = completed_fixture(root)
            artifact = Archive.ld1b_completed_attempt_seal(
                fixture.attempt_dir;
                plan_identity = fixture.plan,
                execution_source_identity = fixture.execution,
                job_identity = fixture.job,
                attempt_number = fixture.attempt_number,
                attempt_role = fixture.attempt_role,
                execution_context = fixture.execution_context,
                terminal_status = fixture.terminal_status,
                terminal_outcome_code = fixture.terminal_outcome_code,
                evidence_manifest_sha256 =
                    fixture.evidence_manifest_sha256,
            )
            old_schema = rehash_archive_artifact(
                artifact;
                schema =
                    "bayesianmgmfrm.local_dependence_pilot_attempt_seal.v1",
            )
            write_archive_json(
                joinpath(
                    fixture.attempt_dir,
                    Archive.LD1B_ATTEMPT_SEAL_FILENAME,
                ),
                old_schema,
            )
            @test_throws Exception validate_completed(fixture)
        end
    end

    @testset "append-only interrupted-attempt retirement" begin
        mktempdir() do root
            fixture = retirement_fixture(root)
            publication = publish_retirement(fixture)
            validation = publication.validation
            @test validation.valid
            @test validation.state === :retired_interrupted
            @test validation.terminal_status === nothing
            @test validation.terminal_outcome_code ===
                :interrupted_attempt_retired_nonterminal
            @test validation.retirement_reason_code === fixture.reason
            @test validation.review_record_sha256 == fixture.review_sha256
            @test publication.artifact.schema ==
                Archive.LD1B_ATTEMPT_RETIREMENT_SCHEMA
            @test Set(propertynames(publication.artifact.attempt)) ==
                Set((:number, :role, :counts_toward_primary))
            @test publication.artifact.attempt.counts_toward_primary
            @test Set(propertynames(publication.artifact.retirement)) == Set((
                :reason_code,
                :review_record_sha256,
                :process_confirmed_stopped,
                :retirement_counts_toward_primary,
            ))
            @test publication.artifact.retirement.
                retirement_counts_toward_primary === false
            @test validation.original_slot_counts_toward_primary === true
            @test validation.retirement_counts_toward_primary === false
            @test !hasproperty(validation, :counts_toward_primary)
            @test validation.same_attempt_restart_allowed === false
            @test validation.remediation_may_replace_primary === false
            @test publication.publication.publication ===
                :same_volume_hardlink_create_new
            @test stat(joinpath(
                fixture.attempt_dir,
                Archive.LD1B_ATTEMPT_RETIREMENT_FILENAME,
            )).nlink == 1
            @test_throws Exception publish_retirement(fixture)
            @test_throws Exception validate_retirement(
                fixture;
                expected_reason_code = :different_reason,
            )
            @test_throws Exception validate_retirement(
                fixture;
                expected_review_record_sha256 = hex64("e"),
            )
        end

        mktempdir() do root
            fixture = retirement_fixture(root)
            @test_throws Exception Archive.ld1b_retirement_marker(
                fixture.attempt_dir;
                plan_identity = fixture.plan,
                execution_source_identity = fixture.execution,
                job_identity = fixture.job,
                attempt_number = fixture.attempt_number,
                attempt_role = fixture.attempt_role,
                retirement_reason_code = fixture.reason,
                review_record_sha256 = fixture.review_sha256,
                process_confirmed_stopped = false,
            )
            @test !ispath(joinpath(
                fixture.attempt_dir,
                Archive.LD1B_ATTEMPT_RETIREMENT_FILENAME,
            ))
        end

        mktempdir() do root
            fixture = retirement_fixture(root)
            publish_retirement(fixture)
            open(fixture.partial_path, "a") do io
                write(io, " ")
            end
            @test_throws Exception validate_retirement(fixture)
        end

        mktempdir() do root
            fixture = retirement_fixture(root)
            publish_retirement(fixture)
            write(joinpath(fixture.attempt_dir, "late_file.txt"), "forbidden")
            @test_throws Exception validate_retirement(fixture)
        end

        mktempdir() do root
            fixture = retirement_fixture(root)
            publish_retirement(fixture)
            write(joinpath(
                fixture.attempt_dir,
                Archive.LD1B_ATTEMPT_SEAL_FILENAME,
            ), "{}")
            @test_throws Exception validate_retirement(fixture)
        end

        mktempdir() do root
            fixture = retirement_fixture(root)
            publish_retirement(fixture)
            retirement_path = joinpath(
                fixture.attempt_dir,
                Archive.LD1B_ATTEMPT_RETIREMENT_FILENAME,
            )
            hardlink(
                retirement_path,
                joinpath(root, "second_retirement_link.json"),
            )
            @test_throws Exception validate_retirement(fixture)
        end

        mktempdir() do root
            fixture = retirement_fixture(root)
            write(joinpath(
                fixture.attempt_dir,
                Archive.LD1B_ATTEMPT_SEAL_FILENAME,
            ), "{}")
            @test_throws Exception Archive.ld1b_retirement_marker(
                fixture.attempt_dir;
                plan_identity = fixture.plan,
                execution_source_identity = fixture.execution,
                job_identity = fixture.job,
                attempt_number = fixture.attempt_number,
                attempt_role = fixture.attempt_role,
                retirement_reason_code = fixture.reason,
                review_record_sha256 = fixture.review_sha256,
                process_confirmed_stopped = true,
            )
        end

        mktempdir() do root
            fixture = retirement_fixture(
                root;
                attempt_number = 2,
                attempt_role = :remediation,
            )
            validation = publish_retirement(fixture).validation
            @test validation.valid
            @test validation.original_slot_counts_toward_primary === false
            @test validation.retirement_counts_toward_primary === false
        end

        mktempdir() do root
            fixture = retirement_fixture(
                root;
                attempt_number = 2,
                attempt_role = :primary,
            )
            @test_throws Exception publish_retirement(fixture)
        end

        @testset "retirement schema semantic split is exact" begin
            mktempdir() do root
                fixture = retirement_fixture(root)
                artifact = Archive.ld1b_retirement_marker(
                    fixture.attempt_dir;
                    plan_identity = fixture.plan,
                    execution_source_identity = fixture.execution,
                    job_identity = fixture.job,
                    attempt_number = fixture.attempt_number,
                    attempt_role = fixture.attempt_role,
                    retirement_reason_code = fixture.reason,
                    review_record_sha256 = fixture.review_sha256,
                    process_confirmed_stopped = true,
                )
                old_schema = rehash_archive_artifact(
                    artifact;
                    schema =
                        "bayesianmgmfrm.local_dependence_pilot_attempt_retirement.v1",
                )
                write_archive_json(joinpath(
                    fixture.attempt_dir,
                    Archive.LD1B_ATTEMPT_RETIREMENT_FILENAME,
                ), old_schema)
                @test_throws Exception validate_retirement(fixture)
            end

            mktempdir() do root
                fixture = retirement_fixture(root)
                artifact = Archive.ld1b_retirement_marker(
                    fixture.attempt_dir;
                    plan_identity = fixture.plan,
                    execution_source_identity = fixture.execution,
                    job_identity = fixture.job,
                    attempt_number = fixture.attempt_number,
                    attempt_role = fixture.attempt_role,
                    retirement_reason_code = fixture.reason,
                    review_record_sha256 = fixture.review_sha256,
                    process_confirmed_stopped = true,
                )
                missing_contribution = rehash_archive_artifact(
                    artifact;
                    retirement = (;
                        reason_code = artifact.retirement.reason_code,
                        review_record_sha256 =
                            artifact.retirement.review_record_sha256,
                        process_confirmed_stopped = true,
                    ),
                )
                write_archive_json(joinpath(
                    fixture.attempt_dir,
                    Archive.LD1B_ATTEMPT_RETIREMENT_FILENAME,
                ), missing_contribution)
                @test_throws Exception validate_retirement(fixture)
            end

            mktempdir() do root
                fixture = retirement_fixture(root)
                artifact = Archive.ld1b_retirement_marker(
                    fixture.attempt_dir;
                    plan_identity = fixture.plan,
                    execution_source_identity = fixture.execution,
                    job_identity = fixture.job,
                    attempt_number = fixture.attempt_number,
                    attempt_role = fixture.attempt_role,
                    retirement_reason_code = fixture.reason,
                    review_record_sha256 = fixture.review_sha256,
                    process_confirmed_stopped = true,
                )
                counting_retirement = rehash_archive_artifact(
                    artifact;
                    retirement = merge(artifact.retirement, (;
                        retirement_counts_toward_primary = true,
                    )),
                )
                write_archive_json(joinpath(
                    fixture.attempt_dir,
                    Archive.LD1B_ATTEMPT_RETIREMENT_FILENAME,
                ), counting_retirement)
                @test_throws Exception validate_retirement(fixture)
            end

            mktempdir() do root
                fixture = retirement_fixture(root)
                artifact = Archive.ld1b_retirement_marker(
                    fixture.attempt_dir;
                    plan_identity = fixture.plan,
                    execution_source_identity = fixture.execution,
                    job_identity = fixture.job,
                    attempt_number = fixture.attempt_number,
                    attempt_role = fixture.attempt_role,
                    retirement_reason_code = fixture.reason,
                    review_record_sha256 = fixture.review_sha256,
                    process_confirmed_stopped = true,
                )
                extra_field = rehash_archive_artifact(
                    artifact;
                    retirement = merge(artifact.retirement, (;
                        unexpected = false,
                    )),
                )
                write_archive_json(joinpath(
                    fixture.attempt_dir,
                    Archive.LD1B_ATTEMPT_RETIREMENT_FILENAME,
                ), extra_field)
                @test_throws Exception validate_retirement(fixture)
            end

            mktempdir() do root
                fixture = retirement_fixture(root)
                artifact = Archive.ld1b_retirement_marker(
                    fixture.attempt_dir;
                    plan_identity = fixture.plan,
                    execution_source_identity = fixture.execution,
                    job_identity = fixture.job,
                    attempt_number = fixture.attempt_number,
                    attempt_role = fixture.attempt_role,
                    retirement_reason_code = fixture.reason,
                    review_record_sha256 = fixture.review_sha256,
                    process_confirmed_stopped = true,
                )
                changed_slot = rehash_archive_artifact(
                    artifact;
                    attempt = merge(artifact.attempt, (;
                        counts_toward_primary = false,
                    )),
                )
                write_archive_json(joinpath(
                    fixture.attempt_dir,
                    Archive.LD1B_ATTEMPT_RETIREMENT_FILENAME,
                ), changed_slot)
                @test_throws Exception validate_retirement(fixture)
            end
        end
    end
end
