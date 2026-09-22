module MFRMAnchorAttemptRecordTests

using Test, SHA, Random, Serialization, JSON3
using BayesianMGMFRM
include(joinpath(@__DIR__, "..", "scripts", "mfrm_anchor_attempt_record.jl"))
const Records = MFRMAnchorAttemptRecord
const Archive = Records.Archive

@testset "M2 record publication recovery (no fits)" begin
    # Opaque test record, not an accepted scientific input/event schema.
    expected = Archive.ld1b_archive_with_content_hash((;
        schema = "test.anchor_record.v1", phase = "test", dataset_id = "D/1",
        heldout_id = "H/1", method = "B", attempt = 1, input_digest = "a"^64))
    original = deepcopy(expected)
    validator = value -> begin
        value["schema"] == "test.anchor_record.v1" && value["phase"] == "test" ||
            error("wrong record context")
        return true
    end
    for fault in (nothing, :pre_link, :post_link_pre_unlink, :post_unlink_pre_validation)
        mktempdir() do root
            target, staging = joinpath(root, "record.json"), joinpath(root, "staging")
            if fault === nothing
                Records.publish_record(target, expected, staging, root; semantic_validator = validator)
            else
                @test_throws Exception Records.publish_record(target, expected, staging, root;
                    semantic_validator = validator, _fault_injection_stage = fault)
            end
            before = isfile(target) ? read(target) : nothing
            recovered = Records.recover_record(target, expected, staging, root; semantic_validator = validator)
            @test recovered.status === (fault === :pre_link ? :not_published : :published)
            @test !recovered.lifecycle_counts_available && !recovered.validation_claim_allowed
            @test recovered.staging_alias_removed == (fault === :post_link_pre_unlink)
            @test recovered.file_sha256 == (before === nothing ? nothing : bytes2hex(sha256(before)))
            @test before === nothing ? !ispath(target) : read(target) == before && stat(target).nlink == 1
            @test fault === :pre_link ? length(readdir(staging)) == 1 : isempty(readdir(staging))
            again = Records.recover_record(target, expected, staging, root; semantic_validator = validator)
            @test again.status === recovered.status && !again.staging_alias_removed
        end
    end
    # Rejection cannot erase/replace either the target or an ambiguous alias.
    for conflict in (:wrong_bytes, :extra_alias, :wrong_staging, :semantic_rejection)
        mktempdir() do root
            target, staging = joinpath(root, "record.json"), joinpath(root, "staging")
            @test_throws Exception Records.publish_record(target, expected, staging, root;
                semantic_validator = validator, _fault_injection_stage = :post_link_pre_unlink)
            alias = only(readdir(staging; join = true))
            conflict === :extra_alias && hardlink(alias, joinpath(staging, "extra"))
            before, links, files = read(target), stat(target).nlink, readdir(staging)
            different = Archive.ld1b_archive_with_content_hash(merge(
                Base.structdiff(expected, (; content_hash = nothing)), (; input_digest = "b"^64)))
            @test_throws Exception Records.recover_record(target,
                conflict === :wrong_bytes ? different : expected,
                conflict === :wrong_staging ? root : staging, root;
                semantic_validator = conflict === :semantic_rejection ? (_ -> error("reject")) : validator)
            @test read(target) == before && stat(target).nlink == links
            @test readdir(staging) == files
        end
    end
    mktempdir() do root
        target, staging = joinpath(root, "record.json"), joinpath(root, "staging")
        @test Records.recover_record(target, expected, staging, root;
            semantic_validator = validator).status === :not_published
        @test isempty(readdir(root)) # No publication or directory creation on recovery.
        for paths in (("relative.json", staging, root),
                (joinpath(root, "..", "outside.json"), staging, root),
                (target, dirname(root), root), (target, root, root))
            @test_throws Exception Records.recover_record(paths[1], expected, paths[2], paths[3];
                semantic_validator = validator)
        end
        @test_throws Exception Records.recover_record(target,
            merge(expected, (; attempt = 2)), staging, root; semantic_validator = validator)
        symlink("absent", target)
        @test_throws Exception Records.recover_record(target, expected, staging, root;
            semantic_validator = validator)
        @test islink(target)
    end
    @test expected == original

    @testset "stopped producer recovery" begin
        # Build the publisher's primitive write/link/unlink states, then SIGKILL
        # our own child before acknowledgement. No fit or Julia package is loaded
        # in that child, and no observer finally-block performs its cleanup.
        code = raw"""
            root, window = ARGS[1], parse(Int, ARGS[2])
            bytes = read(joinpath(root, "expected.json"))
            staging = joinpath(root, "staging")
            mkpath(staging)
            temporary, io = mktemp(staging)
            write(io, window == 0 ? bytes[1:div(length(bytes), 2)] : bytes)
            flush(io)
            if window > 0
                close(io)
            end
            window >= 2 && hardlink(temporary, joinpath(root, "record.json"))
            window == 3 && rm(temporary)
            write(joinpath(root, "ready"), "ready")
            while true
                sleep(1)
            end
        """
        for window in 0:3
            mktempdir() do root
                target, staging = joinpath(root, "record.json"), joinpath(root, "staging")
                bytes = Archive._ld1b_encode_json_bytes(expected)
                write(joinpath(root, "expected.json"), bytes)
                ready = joinpath(root, "ready")
                open(joinpath(root, "child.log"), "w") do log
                    child = run(pipeline(`$(Base.julia_cmd()) --startup-file=no --history-file=no -e $code $root $window`;
                        stdout = log, stderr = log); wait = false)
                    try
                        @test timedwait(() -> isfile(ready) || process_exited(child), 30.0;
                            pollint = 0.05) === :ok
                        isfile(ready) || error("record producer did not reach its test checkpoint")
                        kill(child, Base.SIGKILL)
                        wait(child)
                        @test !success(child)
                    finally
                        process_running(child) && kill(child, Base.SIGKILL)
                        wait(child)
                    end
                end
                recovered = Records.recover_record(target, expected, staging, root;
                    semantic_validator = validator)
                @test recovered.status === (window < 2 ? :not_published : :published)
                @test !recovered.lifecycle_counts_available && !recovered.validation_claim_allowed
                @test recovered.staging_alias_removed == (window == 2)
                if window < 2
                    @test !ispath(target)
                    @test length(readdir(staging)) == 1
                    @test filesize(only(readdir(staging; join = true))) ==
                        (window == 0 ? div(length(bytes), 2) : length(bytes))
                else
                    @test read(target) == bytes && stat(target).nlink == 1
                    @test isempty(readdir(staging))
                    @test recovered.file_sha256 == bytes2hex(sha256(bytes))
                end
                again = Records.recover_record(target, expected, staging, root; semantic_validator = validator)
                @test again.status === recovered.status && !again.staging_alias_removed
            end
        end
    end
end

@testset "M2 fit observation boundary (no sampling)" begin
    data = FacetData((; person = ["P1", "P2"], rater = ["R1", "R1"],
        item = ["I1", "I1"], score = [0, 1]); person = :person, rater = :rater,
        item = :item, score = :score, category_levels = 0:1)
    spec = mfrm_spec(data)
    design = getdesign(spec)
    events = Symbol[]
    record_event = stage -> push!(events, stage)
    caught(f) = try f(); nothing catch err; err end
    rng = MersenneTwister(17) # Test-only ownership check, not an evaluation seed.
    checkpoint = copy(rng)

    # Real public entry, rejected before validation snapshot/RNG selection/sampling.
    for backend in (:julia, :advancedhmc, :turing, :cmdstan), input in (design, spec)
        empty!(events)
        err = caught() do
            Records.observe_fit(; record_event) do on_enter
                fit(input; backend, ndraws = 0, rng, _on_enter = on_enter)
            end
        end
        @test err isa ArgumentError && err.msg == "ndraws must be positive"
        @test events == [:fit_entered]
        @test rng == checkpoint
    end
    empty!(events)
    @test_throws MethodError Records.observe_fit(; record_event) do on_enter
        fit(nothing; _on_enter = on_enter)
    end
    @test isempty(events)
    @test_throws TypeError Records.observe_fit(; record_event) do on_enter
        fit(design; ndraws = 0.5, _on_enter = on_enter)
    end
    @test isempty(events)
    @test_throws ArgumentError fit(design; ndraws = 0) # Default path still rejects.

    failure = ErrorException("recorder failed")
    err = caught() do
        Records.observe_fit(; record_event = _ -> throw(failure)) do on_enter
            fit(design; ndraws = 0, rng, _on_enter = on_enter)
        end
    end
    @test err isa Records.FitObservationError
    @test err.stage === :fit_entered && err.cause.ex === failure
    @test err.returned_fit === nothing && rng == checkpoint
    @test occursin("recorder failed", sprint(showerror, err))

    # Synthetic call results test the wrapper only, never a successful real fit.
    sentinel = Ref(:synthetic_result)
    empty!(events)
    returned = Records.observe_fit(; record_event) do on_enter
        on_enter()
        @test events == [:fit_entered]
        sentinel
    end
    @test returned === sentinel && events == [:fit_entered, :fit_returned]
    empty!(events)
    call_failure = ErrorException("synthetic call failed")
    err = caught() do
        Records.observe_fit(; record_event) do on_enter
            on_enter()
            throw(call_failure)
        end
    end
    @test err === call_failure && events == [:fit_entered]
    empty!(events)
    @test_throws Records.FitObservationError Records.observe_fit(; record_event) do on_enter
        on_enter()
        on_enter()
    end
    @test events == [:fit_entered]
    empty!(events)
    err = caught(() -> Records.observe_fit(_ -> sentinel; record_event))
    @test err isa Records.FitObservationError && isempty(events)
    @test err.returned_fit === sentinel

    # Reuse the real publisher with opaque test declarations/event records.
    # Publication ordering/hash linkage here is not an audit of scientific inputs.
    for fail_at in (:fit_entered, :fit_returned)
        mktempdir() do root
            staging = joinpath(root, "staging")
            declaration = Archive.ld1b_archive_with_content_hash((;
                schema = "test.input.v1", attempt = 1, phase = "test"))
            validate_input = value -> (@assert value["schema"] == "test.input.v1")
            input_path = joinpath(root, "input.json")
            Records.publish_record(input_path, declaration, staging, root;
                semantic_validator = validate_input)
            input_bytes = read(input_path)
            records = Dict(stage => Archive.ld1b_archive_with_content_hash((;
                schema = "test.event.v1", stage, input_hash = declaration.content_hash.value))
                for stage in (:fit_entered, :fit_returned))
            validate_event = value -> begin
                @assert value["schema"] == "test.event.v1"
                @assert value["input_hash"] == declaration.content_hash.value
            end
            recorder = stage -> Records.publish_record(joinpath(root, "$stage.json"),
                records[stage], staging, root; semantic_validator = validate_event,
                _fault_injection_stage = stage === fail_at ? :post_link_pre_unlink : nothing)
            err = caught() do
                Records.observe_fit(; record_event = recorder) do on_enter
                    if fail_at === :fit_entered
                        fit(design; ndraws = 0, _on_enter = on_enter)
                    else
                        on_enter()
                        sentinel # Synthetic return, not a sampler result.
                    end
                end
            end
            @test err isa Records.FitObservationError && err.stage === fail_at
            @test err.returned_fit === (fail_at === :fit_returned ? sentinel : nothing)
            @test read(input_path) == input_bytes
            @test isfile(joinpath(root, "fit_returned.json")) == (fail_at === :fit_returned)
            recovered = Records.recover_record(joinpath(root, "$fail_at.json"),
                records[fail_at], staging, root; semantic_validator = validate_event)
            @test recovered.status === :published && recovered.staging_alias_removed
            @test !recovered.lifecycle_counts_available && !recovered.validation_claim_allowed
        end
    end
end

@testset "M2 declared fit input binding (no sampling)" begin
    panel(; scores = nothing, prefix = "P") = FacetData((;
        person = ["$prefix$p" for p in 1:2 for r in 1:2 for i in 1:2],
        rater = ["R$r" for p in 1:2 for r in 1:2 for i in 1:2],
        item = ["I$i" for p in 1:2 for r in 1:2 for i in 1:2],
        score = scores === nothing ? [mod(p + r + i, 2)
            for p in 1:2 for r in 1:2 for i in 1:2] : scores);
        person = :person, rater = :rater, item = :item, score = :score,
        category_levels = 0:1)
    design = getdesign(mfrm_spec(panel()))
    options = (; prior = MFRMPrior(), backend = :julia, ndraws = 0, warmup = 0,
        chains = 1, step_size = 0.05, init = nothing, rng = MersenneTwister(17),
        seed = nothing, target_accept = 0.8, max_depth = 10,
        max_energy_error = 1000.0, metric = :diagonal, ad_backend = :ForwardDiff,
        init_jitter = 0.0, progress = false, cmdstan_path = nothing, cmdstan_cache_dir = nothing)
    @test Set(Base.kwarg_decl(which(fit, (FacetDesign,)))) ==
        union(Set(keys(options)), Set((:_on_enter,)))
    rand(options.rng, 11) # Test state only; not an evaluation allocation.
    checkpoint = copy(options.rng)
    input = Records.fit_input_record(design; options)
    @test input["schema"] == "bayesianmgmfrm.anchor_fit_input.v2"
    @test input["design_identity"] == Archive._ld1b_json_native(
        Base.structdiff(design_identity(design), (; data_signature = nothing)))
    @test Archive.ld1b_archive_canonical_sha256(input) == Archive.ld1b_archive_canonical_sha256(
        Archive._ld1b_json_native(JSON3.read(String(Archive._ld1b_encode_json_bytes(input)))))
    @test input == Records.fit_input_record(design; options)
    @test options.rng == checkpoint
    @test input["initialization"]["policy"] == "default_zero"
    @test input["initialization"]["values"] == zeros(length(design.parameter_names))
    @test input["design"]["data"]["score"] == design.spec.data.score
    @test input["rng"]["sha256"] == bytes2hex(sha256(UInt8.(input["rng"]["state"])))
    replay = deserialize(IOBuffer(UInt8.(input["rng"]["state"]))) # Only our own generated bytes.
    @test replay == checkpoint && rand(replay, 5) == rand(copy(checkpoint), 5)
    prepared = Records._prepare_fit_inputs(design, options)
    @test prepared.design !== design && prepared.options.rng !== options.rng
    @test prepared.options.rng == checkpoint
    rand(prepared.options.rng)
    @test options.rng == checkpoint
    seeded = merge(options, (; seed = 29))
    @test Records.fit_input_record(design; options = seeded) ==
        Records.fit_input_record(design; options = merge(seeded, (; rng = Random.default_rng())))
    @test Records.fit_input_record(design; options = seeded)["rng"] == Dict(
        "mode" => "explicit_seed", "algorithm" => "MersenneTwister", "seed" => 29)

    for invalid in (merge(options, (; rng = Random.default_rng())),
            merge(options, (; seed = true)), merge(options, (; seed = "17")),
            merge(options, (; seed = big(typemax(Int)) + 1)),
            merge(options, (; ndraws = true)), merge(options, (; step_size = Inf)),
            merge(options, (; backend = :unknown)), merge(options, (; progress = 1)),
            merge(options, (; init = zeros(length(design.parameter_names), 1))),
            merge(options, (; init = [NaN])), merge(options, (; _on_enter = () -> nothing)),
            Base.structdiff(options, (; warmup = nothing)))
        @test_throws Exception Records.fit_input_record(design; options = invalid)
    end
    @test options.rng == checkpoint

    mktempdir() do root
        path, staging = joinpath(root, "input.json"), joinpath(root, "staging")
        expected = Archive.ld1b_archive_with_content_hash((; schema = "test.declaration.v1",
            phase = "test", attempt = 1, fit_input = input))
        validator = value -> (@assert value["schema"] == "test.declaration.v1" &&
            value["phase"] == "test" && value["attempt"] == 1)
        events = Any[]
        recorder = (stage, binding) -> push!(events, (; stage, binding))
        caught(f) = try f(); nothing catch err; err end
        call(; input_design = design, actual_options = options, declaration = expected,
                input_path = path, validate = validator) = Records.observe_declared_fit(
            input_design; options = actual_options, path = input_path, expected = declaration,
            boundary = root, semantic_validator = validate, record_event = recorder)
        @test_throws Exception call() # Missing file: never publish or start implicitly.
        @test isempty(events) && isempty(readdir(root))
        Records.publish_record(path, expected, staging, root; semantic_validator = validator)
        before = read(path)
        err = caught(() -> call())
        @test err isa ArgumentError && err.msg == "ndraws must be positive"
        @test only(events).stage === :fit_entered
        @test only(events).binding == (; input_content_hash = expected.content_hash.value,
            input_file_sha256 = bytes2hex(sha256(before)))
        @test options.rng == checkpoint && read(path) == before
        empty!(events)

        # Every effective argument and each explicit inactive setting is bound.
        changes = ((; prior = MFRMPrior(person_sd = 2.0)), (; backend = :advancedhmc),
            (; ndraws = 1), (; warmup = 1), (; chains = 2), (; step_size = 0.06),
            (; init = zeros(length(design.parameter_names))), (; rng = MersenneTwister(29)),
            (; seed = 17), (; target_accept = 0.9), (; max_depth = 9),
            (; max_energy_error = 999.0), (; metric = :unit), (; ad_backend = :analytic),
            (; init_jitter = 0.01), (; progress = true),
            (; cmdstan_path = "/test/cmdstan"), (; cmdstan_cache_dir = "/test/cache"))
        for change in changes
            @test_throws ArgumentError call(; actual_options = merge(options, change))
            @test isempty(events) && read(path) == before
        end
        for changed in (getdesign(mfrm_spec(panel(; prefix = "Q"))),
                getdesign(mfrm_spec(panel(; scores = 1 .- design.spec.data.score))),
                getdesign(mfrm_spec(panel(); thresholds = :rating_scale)),
                getdesign(mfrm_spec(panel(); anchors = [
                    (; block = :rater, level = "R2", value = 0.5, type = :hard)])))
            @test Records.fit_input_record(changed; options) != input
            @test_throws ArgumentError call(; input_design = changed)
            @test isempty(events)
        end
        stale = deepcopy(design)
        stale.parameter_names[1] = "stale"
        @test_throws ArgumentError call(; input_design = stale)
        @test_throws Exception call(; declaration = merge(expected, (; attempt = 2)))
        @test_throws Exception call(; validate = _ -> error("scope rejected"))
        @test_throws Exception call(; input_path = "relative.json")
        @test_throws Exception call(; input_path = joinpath(root, "..", "outside.json"))
        link = joinpath(root, "alias.json")
        hardlink(path, link)
        @test_throws Exception call()
        @test stat(path).nlink == 2 && isfile(link) # No implicit alias recovery.
        rm(link) # This test's own link, not a declaration or recovered evidence.
        symlink(path, link)
        @test_throws Exception call(; input_path = link)
        @test islink(link)
        altered = Archive.ld1b_archive_with_content_hash((; schema = "test.declaration.v1",
            phase = "test", attempt = 1, fit_input = input, extra = "different bytes"))
        @test_throws ArgumentError call(; declaration = altered)
        legacy_input = merge(input, Dict("schema" => "bayesianmgmfrm.anchor_fit_input.v1"))
        legacy = Archive.ld1b_archive_with_content_hash((; schema = "test.declaration.v1",
            phase = "test", attempt = 1, fit_input = legacy_input))
        legacy_path = joinpath(root, "legacy-input.json")
        Records.publish_record(legacy_path, legacy, staging, root; semantic_validator = validator)
        @test_throws ArgumentError call(; declaration = legacy, input_path = legacy_path)
        @test read(legacy_path) == Archive._ld1b_encode_json_bytes(legacy)
        @test isempty(events) && read(path) == before && options.rng == checkpoint
    end

    # A callback mutating caller-owned arrays after preflight cannot change the
    # private call. Invalid target_accept stops the real AHMC adapter before any
    # target/draw allocation, jitter, or sampling, after design/init validation.
    mktempdir() do root
        owned_design = deepcopy(design)
        actual_options = merge(options, (; backend = :advancedhmc, ndraws = 1,
            target_accept = 2.0, init = zeros(length(design.parameter_names))))
        expected = Archive.ld1b_archive_with_content_hash((; fit_input =
            Records.fit_input_record(owned_design; options = actual_options)))
        path = joinpath(root, "input.json")
        Records.publish_record(path, expected, joinpath(root, "staging"), root;
            semantic_validator = _ -> nothing)
        seen = Symbol[]
        err = try
            Records.observe_declared_fit(owned_design; options = actual_options,
                path, expected, boundary = root, semantic_validator = _ -> nothing,
                record_event = (stage, binding) -> begin
                    push!(seen, stage)
                    owned_design.parameter_names[1] = "corrupted by caller"
                    actual_options.init[1] = NaN
                    rand(actual_options.rng)
                end)
            nothing
        catch error
            error
        end
        @test err isa ArgumentError && err.msg == "target_accept must be in (0, 1) after Float64 conversion"
        @test seen == [:fit_entered]
        @test isnan(actual_options.init[1]) && owned_design.parameter_names[1] == "corrupted by caller"
    end
end

@testset "M2 returned fit and scoring links (no sampling)" begin
    # Synthetic posterior object and manually constructed observations below
    # test linkage only; they are explicitly not evidence that a fit returned.
    rows = [(; person = "P$p", rater = "R$r", item = "I$i", score = mod(p + r + i, 3))
        for p in 1:2 for r in 1:2 for i in 1:2]
    training = (; dataset_id = "test/train", role = "train", category_levels = 0:2, rows)
    heldout = merge(training, (; dataset_id = "test/heldout", role = "heldout"))
    raw(value) = collect(codeunits(JSON3.write(value)))
    response_ref(value) = (; value.dataset_id, value.role, sha256 = bytes2hex(sha256(raw(value))))
    train_bytes, heldout_bytes = raw(training), raw(heldout)
    data = BayesianMGMFRM._mfrm_anchor_response_data(train_bytes, response_ref(training))
    design = getdesign(mfrm_spec(data; thresholds = :rating_scale))
    prior = MFRMPrior()
    fitted = MFRMFit(design, prior, 0.2 .* randn(MersenneTwister(17), 160,
        length(design.parameter_names)), zeros(160), 0.5, repeat(1:4; inner = 40),
        repeat(1:40, 4), fill(0.5, 4), :julia, :random_walk_metropolis, 0, 0.05)
    truth = [merge(row, (; category, log_probability = -log(3.0))) for row in rows for category in 0:2]
    source = abspath(joinpath(@__DIR__, "..", "src", "bayesian_fit.jl"))
    reference = (; training.dataset_id, heldout_id = heldout.dataset_id,
        method = "test/mfrm", attempt = 1, training = response_ref(training), heldout = response_ref(heldout),
        truth_sha256 = BayesianMGMFRM._cache_hash(truth), source_files = Dict(source => bytes2hex(sha256(read(source)))),
        diagnostic_policy = (; split_chains = true, rhat_threshold = 1.2, ess_threshold = 20, min_e_bfmi = 0.3),
        contrasts = NamedTuple[], cell = nothing)
    options = (; prior, backend = :julia, ndraws = 40, warmup = 0, chains = 4,
        step_size = 0.05, init = nothing, rng = MersenneTwister(29), seed = 17,
        target_accept = 0.8, max_depth = 10, max_energy_error = 1000.0,
        metric = :diagonal, ad_backend = :ForwardDiff, init_jitter = 0.0, progress = false,
        cmdstan_path = nothing, cmdstan_cache_dir = nothing)
    declaration(opts) = Archive.ld1b_archive_with_content_hash((;
        schema = "test.declaration.v1", phase = "test", reference.dataset_id,
        reference.heldout_id, reference.method, reference.attempt,
        scoring_plan_sha256 = BayesianMGMFRM._cache_hash(reference),
        fit_input = Records.fit_input_record(design; options = opts)))
    validator = value -> (@assert value["schema"] == "test.declaration.v1" && value["phase"] == "test")
    caught(f) = try f(); nothing catch err; err end
    for bad in (merge(reference, (; fit_sha256 = "a"^64)),
            merge(reference, (; fit_provenance = nothing)), merge(reference, (; method = "other")),
            merge(reference, (; attempt = 2)), merge(reference, (; attempt = true)),
            merge(reference, (; diagnostic_policy = merge(reference.diagnostic_policy, (; ess_threshold = 19)))))
        @test_throws Exception Records._check_scoring_plan(Archive._ld1b_json_native(declaration(options)), bad)
    end
    binding0 = (; input_content_hash = "a"^64, input_file_sha256 = "b"^64)
    @test_throws ArgumentError Records.fit_event_record(:fit_failed, binding0)
    @test_throws ArgumentError Records.fit_event_record(:fit_entered,
        merge(binding0, (; input_file_sha256 = "b"^64 * "\n")))

    # Exercise the concrete wrapper with a real public call, but stop at its
    # first input guard. A failed/unpublished entry recorder also fails closed.
    for recorder_mode in (:valid, :wrong_stage, :missing)
        mktempdir() do root
            rejected = merge(options, (; ndraws = 0))
            expected = declaration(rejected)
            path, staging = joinpath(root, "input.json"), joinpath(root, "staging")
            Records.publish_record(path, expected, staging, root; semantic_validator = validator)
            stages = Symbol[]
            err = caught() do
                Records.observe_linked_fit(design; reference, options = rejected, path, expected,
                    boundary = root, semantic_validator = validator,
                    record_event = (stage, binding) -> begin
                        push!(stages, stage)
                        event_path = joinpath(root, "$stage.json")
                        if recorder_mode !== :missing
                            event = Records.fit_event_record(recorder_mode === :wrong_stage ? :fit_returned : stage, binding)
                            Records.publish_record(event_path, event, staging, root; semantic_validator = _ -> nothing)
                        end
                        event_path
                    end)
            end
            @test stages == [:fit_entered] && !isfile(joinpath(root, "fit_returned.json"))
            if recorder_mode === :valid
                @test err isa ArgumentError && err.msg == "ndraws must be positive"
            else
                @test err isa Records.FitObservationError && err.stage === :fit_entered
                @test err.returned_fit === nothing
            end
            @test read(path) == Archive._ld1b_encode_json_bytes(expected)
        end
    end

    mktempdir() do root
        staging = joinpath(root, "staging")
        publish(name, record) = begin
            path = joinpath(root, name)
            Records.publish_record(path, record, staging, root; semantic_validator = _ -> nothing)
            Records._verified_record(path, record, root; semantic_validator = _ -> nothing).reference
        end
        input = publish("input.json", declaration(options))
        binding = (; input_content_hash = input.content_hash, input_file_sha256 = input.file_sha256)
        entered = publish("entered.json", Records.fit_event_record(:fit_entered, binding))
        returned = publish("returned.json", Records.fit_event_record(:fit_returned, binding))
        linked = Records._link_returned_fit(fitted, reference, (; input, entered, returned))
        @test linked.fit === fitted
        @test linked.reference.fit_sha256 == BayesianMGMFRM._mfrm_anchor_fit_hash(fitted)
        @test linked.link.reference_sha256 == BayesianMGMFRM._cache_hash(linked.reference)
        link_ref = publish("link.json", linked.link)
        score(; object = fitted, ref = linked.reference, training_data = train_bytes,
            expected = linked.link, path = link_ref.path) = Records.score_linked_fit(object,
                training_data, heldout_bytes, truth; reference = ref, path, expected, boundary = root)
        before = Dict(ref.path => read(ref.path) for ref in (input, entered, returned, link_ref))
        fitted_hash = BayesianMGMFRM._mfrm_anchor_fit_hash(fitted)
        report = score()
        @test report.status === :scored && !report.validation_claim_allowed
        @test report.reference.fit_provenance == linked.reference.fit_provenance
        @test report.content_hash == artifact_content_hash(report)
        key = (reference.dataset_id, reference.heldout_id, reference.method, reference.attempt)
        plan = [merge(reference, (; reference_sha256 = BayesianMGMFRM._cache_hash(linked.reference)))]
        @test isequal(only(BayesianMGMFRM._mfrm_anchor_checked_primary(plan, [report],
            Dict(key => BayesianMGMFRM._cache_hash(report)))), report)
        # The generic artifact hash omits nested content_hash fields. The
        # retained full-reference/attempt hashes must still bind those fields.
        changed_provenance = merge(report.reference.fit_provenance,
            (; input = merge(input, (; content_hash = "0"^64))))
        tampered = merge(report, (; reference = merge(report.reference,
            (; fit_provenance = changed_provenance))))
        @test artifact_content_hash(tampered) == report.content_hash
        @test_throws ArgumentError BayesianMGMFRM._mfrm_anchor_checked_primary(plan,
            [tampered], Dict(key => BayesianMGMFRM._cache_hash(report)))
        @test_throws ArgumentError BayesianMGMFRM._mfrm_anchor_checked_primary(plan,
            [tampered], Dict(key => BayesianMGMFRM._cache_hash(tampered)))
        changed = deepcopy(fitted)
        changed.draws[1, 1] += 0.1
        @test_throws ArgumentError score(; object = changed)
        @test_throws ArgumentError score(; ref = merge(linked.reference, (; method = "other")))
        err = caught(() -> score(; training_data = UInt8[0]))
        @test err isa ArgumentError && !(err isa Records.FitObservationError)
        @test BayesianMGMFRM._mfrm_anchor_fit_hash(fitted) == fitted_hash
        @test all(read(path) == bytes for (path, bytes) in before)

        for ref in (input, entered, returned, link_ref)
            backup = ref.path * ".test-backup"
            mv(ref.path, backup)
            try
                @test_throws Exception score()
                @test !ispath(ref.path) && isfile(backup) # No recovery or publication by scoring.
            finally
                mv(backup, ref.path)
            end
        end
        # A valid content hash cannot hide changed publication bytes or hard links.
        open(input.path, "a") do io
            write(io, "\n")
        end
        @test_throws Exception score()
        @test read(input.path) == [before[input.path]; UInt8('\n')]
        write(input.path, before[input.path]) # Restore only this test's own fixture.
        alias = joinpath(root, "input-alias.json")
        hardlink(input.path, alias)
        @test_throws Exception score()
        @test stat(input.path).nlink == 2 && isfile(alias)
        rm(alias)

        # Self-consistent link hashes still cannot relabel an entry as a return
        # or splice an event bound to another declaration.
        bad_event = publish("wrong-input.json", Records.fit_event_record(:fit_returned,
            merge(binding, (; input_file_sha256 = "0"^64))))
        for (n, bad_return) in enumerate((entered, bad_event))
            bad = Records._link_returned_fit(fitted, reference, (; input, entered, returned = bad_return))
            bad_path = publish("bad-link-$n.json", bad.link).path
            @test_throws ArgumentError score(; ref = bad.reference, expected = bad.link, path = bad_path)
        end
        fault_path = joinpath(root, "interrupted-link.json")
        @test_throws Exception Records.publish_record(fault_path, linked.link, staging, root;
            semantic_validator = _ -> nothing, _fault_injection_stage = :post_link_pre_unlink)
        @test_throws Exception score(; path = fault_path)
        recovered = Records.recover_record(fault_path, linked.link, staging, root; semantic_validator = _ -> nothing)
        @test recovered.staging_alias_removed && !recovered.lifecycle_counts_available
        @test score(; path = fault_path).status === :scored
        sentinel = Ref(:synthetic_bad_result)
        err = caught(() -> Records._link_returned_fit(sentinel, reference, (; input, entered, returned)))
        @test err isa Records.FitObservationError && err.stage === :fit_linked
        @test err.returned_fit === sentinel
        @test all(read(path) == bytes for (path, bytes) in before)
    end
end

@testset "M2 pre-entry source and environment checks (no sampling)" begin
    data = FacetData((; person = ["P1", "P2"], rater = ["R1", "R1"],
        item = ["I1", "I1"], score = [0, 1]); person = :person, rater = :rater,
        item = :item, score = :score, category_levels = 0:1)
    design = getdesign(mfrm_spec(data))
    options = (; prior = MFRMPrior(), backend = :julia, ndraws = 0, warmup = 0,
        chains = 1, step_size = 0.05, init = nothing, rng = MersenneTwister(17),
        seed = nothing, target_accept = 0.8, max_depth = 10,
        max_energy_error = 1000.0, metric = :diagonal, ad_backend = :ForwardDiff,
        init_jitter = 0.0, progress = false, cmdstan_path = nothing, cmdstan_cache_dir = nothing)
    checkpoint = copy(options.rng)
    previous_project = Base.ACTIVE_PROJECT[]
    original_project = Base.active_project()
    try
        mktempdir() do root
            project, manifest = joinpath(root, "Project.toml"), joinpath(root, "locked.toml")
            source, extra = joinpath(root, "source.jl"), joinpath(root, "extra.jl")
            # These owned files test resolution/bytes only. They are not an
            # installed dependency environment or an executed source roster.
            write(project, "manifest = \"locked.toml\"\n")
            write(manifest, "# test-only lock\n")
            write(joinpath(root, "Manifest.toml"), read(manifest)) # Same-byte fallback.
            write(source, "# source fixture, never included\n")
            write(extra, "# extra fixture, never included\n")
            files = (source, project, manifest, extra)
            before = Dict(path => read(path) for path in files)
            reference = (; dataset_id = "test/train", heldout_id = "test/heldout",
                method = "test/mfrm", attempt = 1,
                required_source_paths = (source, project, manifest),
                source_files = Dict(path => bytes2hex(sha256(before[path])) for path in files),
                project_environment = (; active_project = project, manifest))
            retained = deepcopy(reference)
            input = Records.fit_input_record(design; options)
            declaration(ref) = Archive.ld1b_archive_with_content_hash((;
                schema = "test.source_environment.v1", phase = "test", ref.dataset_id,
                ref.heldout_id, ref.method, ref.attempt,
                scoring_plan_sha256 = BayesianMGMFRM._cache_hash(ref), fit_input = input))
            expected = declaration(reference)
            path, staging = joinpath(root, "input.json"), joinpath(root, "staging")
            Records.publish_record(path, expected, staging, root; semantic_validator = _ -> nothing)
            input_bytes = read(path)
            events = Symbol[]
            call(; ref = reference, saved = expected, input_path = path) = Records.observe_linked_fit(
                design; reference = ref, options, path = input_path, expected = saved, boundary = root,
                semantic_validator = value -> begin
                    @assert value["schema"] == "test.source_environment.v1" && value["phase"] == "test"
                    Records.check_source_environment(value, ref)
                end,
                record_event = (stage, binding) -> begin
                    push!(events, stage)
                    event_path = joinpath(root, "$stage.json")
                    Records.publish_record(event_path, Records.fit_event_record(stage, binding),
                        staging, root; semantic_validator = _ -> nothing)
                    event_path
                end)
            Base.set_active_project(project)
            @test Records.check_source_environment(expected, reference) === nothing
            @test Records.check_source_environment(declaration(merge(reference,
                (; required_source_paths = reverse(reference.required_source_paths)))),
                merge(reference, (; required_source_paths = reverse(reference.required_source_paths)))) === nothing
            err = try call(); nothing catch error; error end
            @test err isa ArgumentError && err.msg == "ndraws must be positive"
            @test events == [:fit_entered] && !isfile(joinpath(root, "fit_returned.json"))
            entered_bytes = read(joinpath(root, "fit_entered.json"))
            empty!(events)

            # Self-consistently hash/publish invalid references, so rejection
            # tests the semantic boundary, not just a stale declaration hash.
            bad_refs = [
                Base.structdiff(reference, (; project_environment = nothing)),
                Base.structdiff(reference, (; source_files = nothing)),
                Base.structdiff(reference, (; required_source_paths = nothing)),
                merge(reference, (; required_source_paths = nothing)),
                merge(reference, (; required_source_paths = ())),
                merge(reference, (; required_source_paths = (source, project, manifest, source))),
                merge(reference, (; required_source_paths = (source, manifest))),
                merge(reference, (; required_source_paths = (source, project))),
                merge(reference, (; project_environment = (; active_project = nothing, manifest))),
                merge(reference, (; project_environment = (; active_project = "Project.toml", manifest))),
                merge(reference, (; project_environment = merge(reference.project_environment, (; extra = true))))]
            append!(bad_refs, [merge(reference, (; source_files = Dict(k => v
                for (k, v) in reference.source_files if k != removed))) for removed in (source, project, manifest)])
            append!(bad_refs, [merge(reference, (; source_files = merge(reference.source_files,
                Dict(extra => digest)))) for digest in ("0"^64, "A"^64, "a"^63, "a"^64 * "\n")])
            push!(bad_refs, merge(reference, (; source_files = merge(reference.source_files,
                Dict("relative.jl" => "a"^64)))))
            push!(bad_refs, merge(reference, (; source_files = merge(reference.source_files,
                Dict(joinpath(root, "..", basename(root), "extra.jl") => reference.source_files[extra])))))
            fallback = joinpath(root, "Manifest.toml")
            push!(bad_refs, merge(reference, (;
                required_source_paths = (source, project, fallback),
                source_files = merge(reference.source_files, Dict(fallback => reference.source_files[manifest])),
                project_environment = (; active_project = project, manifest = fallback))))
            for (n, ref) in enumerate(bad_refs)
                saved = declaration(ref)
                invalid_path = joinpath(root, "invalid-$n.json")
                Records.publish_record(invalid_path, saved, staging, root; semantic_validator = _ -> nothing)
                @test_throws Union{ArgumentError, ErrorException} call(; ref, saved, input_path = invalid_path)
                @test isempty(events) && read(invalid_path) == Archive._ld1b_encode_json_bytes(saved)
            end
            @test_throws ArgumentError Records.check_source_environment(expected,
                merge(reference, (; required_source_paths = reverse(reference.required_source_paths))))

            try
                write(project, "manifest = [not valid TOML")
                ref = merge(reference, (; source_files = merge(reference.source_files,
                    Dict(project => bytes2hex(sha256(read(project)))))))
                saved = declaration(ref) # Matching bytes cannot hide failed native resolution.
                invalid_path = joinpath(root, "malformed-project.json")
                Records.publish_record(invalid_path, saved, staging, root; semantic_validator = _ -> nothing)
                @test_throws ArgumentError call(; ref, saved, input_path = invalid_path)
                @test isempty(events) && read(project, String) == "manifest = [not valid TOML"
            finally
                write(project, before[project])
            end

            for target in files
                try
                    write(target, [before[target]; UInt8('\n')])
                    @test_throws ArgumentError call()
                    @test isempty(events) && read(target) == [before[target]; UInt8('\n')]
                finally
                    write(target, before[target])
                end
                backup = target * ".test-backup"
                mv(target, backup)
                try
                    if target == manifest
                        @test BayesianMGMFRM._evidence_manifest_path(project) == joinpath(root, "Manifest.toml")
                    end
                    @test_throws ArgumentError call()
                    @test isempty(events) && !ispath(target) && isfile(backup)
                finally
                    mv(backup, target)
                end
            end
            other = mkpath(joinpath(root, "other-environment"))
            other_project = joinpath(other, "Project.toml")
            write(other_project, before[project])
            write(joinpath(other, "locked.toml"), before[manifest])
            try
                Base.set_active_project(other_project)
                @test BayesianMGMFRM._evidence_project_hashes()["active_project_sha256"] == reference.source_files[project]
                @test BayesianMGMFRM._evidence_project_hashes()["manifest_sha256"] == reference.source_files[manifest]
                @test_throws ArgumentError call() # Equal bytes cannot conceal a different active environment.
                @test isempty(events)
            finally
                Base.set_active_project(project)
            end
            @test Records.check_source_environment(expected, reference) === nothing
            @test read(path) == input_bytes && read(joinpath(root, "fit_entered.json")) == entered_bytes
            @test reference == retained && options.rng == checkpoint
            @test all(read(path) == bytes for (path, bytes) in before)
        end
    finally
        Base.set_active_project(previous_project)
    end
    @test Base.active_project() == original_project
end

end # module
