module MGMFRMNormalizedSampleChecks

using Test, BayesianMGMFRM, Serialization
const B = BayesianMGMFRM
include("test_groups.jl")

function sample_target(prior_model)
    cells = [(p, i, r) for p in 1:2 for i in 1:4 for r in 1:3]
    ids = prior_model === :source ? [:judge_a, :judge_b, :judge_c] : [11, 22, 33]
    data = FacetData((; person = [p for (p, i, r) in cells],
        item = [i for (p, i, r) in cells], rater = [ids[r] for (p, i, r) in cells],
        score = [mod(p + i + r, 4) for (p, i, r) in cells]);
        person = :person, item = :item, rater = :rater, score = :score, category_levels = 0:3)
    q = prior_model === :source ? Bool[1 0; 1 1; 0 1; 0 1] : Bool[1 0; 1 0; 0 1; 0 1]
    spec = mfrm_spec(data; family = :mgmfrm, dimensions = 2,
        thresholds = :partial_credit, q_matrix = q)
    return B._MGMFRMNormalizedPriorLogDensity(spec; prior_model,
        scales = (; person_sd = 0.7, rater_sd = 0.4, item_sd = 0.6,
            log_discrimination_sd = 0.3, log_consistency_sd = 0.35, step_sd = 0.5),
        source_rater = prior_model === :source ? :judge_b : nothing)
end

const targets = [sample_target(model) for model in (:exchangeable, :source)]
const controls = (; ndraws = 12, warmup = 10, chains = 2, seed = 9173,
    step_size = 0.03, max_depth = 4, init_jitter = 0.02)

@testset "normalized-prior sampling rejects invalid controls before execution" begin
    for target in targets
        @test_throws ArgumentError B._mgmfrm_normalized_prior_sample(target; backend = :julia)
        for backend in (:advancedhmc, :cmdstan)
            @test_throws ArgumentError B._mgmfrm_normalized_prior_sample(target;
                backend, ndraws = 0)
            @test_throws ArgumentError B._mgmfrm_normalized_prior_sample(target,
                fill(NaN, B.LogDensityProblems.dimension(target)); backend)
            @test_throws ArgumentError B._mgmfrm_normalized_prior_sample(target, [0.0]; backend)
        end
        @test_throws ArgumentError B.Experimental.fit(target.base.design.spec; prior = target)
        @test_throws ArgumentError fit_cache_key(target.base.design.spec;
            prior = B._mgmfrm_normalized_prior_record(target))
    end
end

@testset "normalized-prior CmdStan parser verifies lp as well as likelihood (synthetic)" begin
    for target in targets
        raw = initial_params(target)
        pointwise = B._mgmfrm_source_pointwise_loglikelihood_from_unconstrained(target.base.design, raw)
        lp = B.LogDensityProblems.logdensity(target, raw)
        constant = B._source_fixture_logprior(target.base, raw)
        header = ["lp__", "accept_stat__", "stepsize__", "treedepth__",
            "n_leapfrog__", "divergent__", "energy__",
            ["beta.$i" for i in eachindex(raw)]..., ["log_lik.$i" for i in eachindex(pointwise)]...]
        values = [lp - constant, 0.8, 0.03, 1.0, 1.0, 0.0, 10.0, raw..., pointwise...]
        mktempdir() do directory
            path = joinpath(directory, "synthetic.csv")
            write_csv() = write(path, join(header, ',') * "\n" * join(values, ',') * "\n")
            write_csv()
            parsed = B._cmdstan_generalized_chain_result(path, target, 2, 1)
            @test parsed.logps == [lp]
            @test only(parsed.stats).chain == 2
            values[1] += 0.5 # Correct draws/log_lik, wrong prior contribution.
            write_csv()
            error = try
                B._cmdstan_generalized_chain_result(path, target, 2, 1)
                nothing
            catch err
                err
            end
            @test error isa CmdStanError && error.stage === :output_parse &&
                error.reason === :log_posterior_mismatch
        end
    end
end

function check_samples(target, backend, directory)
    backend_options = backend === :cmdstan ?
        (; cmdstan_cache_dir = joinpath(directory, "compile")) : (;)
    result = B._mgmfrm_normalized_prior_sample(target; backend, controls..., backend_options...)
    (; record, diagnostics) = result
    run = record.run
    identity = B._mgmfrm_normalized_prior_identity(target)
    @test !result.public_fit
    @test record.target_identity == identity
    @test isequal(record.prior, B._mgmfrm_normalized_prior_record(target))
    @test run.backend === backend && run.sampler === :nuts
    @test run.controls.rng.seed == controls.seed
    @test size(run.draws) == (24, B.LogDensityProblems.dimension(target))
    @test run.chain_ids == repeat(1:2; inner = 12)
    @test run.iterations == repeat(1:12; outer = 2)
    @test result.raw_parameter_names == target.base.blueprint.parameter_names
    @test result.direct_parameter_names == target.base.blueprint.constrained_parameter_names
    @test diagnostics.n_failed_direct_constraints == 0
    @test diagnostics.n_nonfinite_direct_loglikelihood == 0
    @test !isempty(diagnostics.parameter_rows) && !isempty(diagnostics.direct_parameter_rows)
    @test diagnostics.flag != :ok # Deliberately short operability check, not convergence evidence.
    for (row, raw) in enumerate(eachrow(run.draws))
        pointwise = B._mgmfrm_source_pointwise_loglikelihood_from_unconstrained(target.base.design, raw)
        @test diagnostics.direct_values.pointwise_loglikelihood[row, :] ≈ pointwise atol = 1e-10
        @test run.logdensities[row] ≈ sum(pointwise) + logprior(target, raw) atol = 1e-9
        @test run.sampler_stats[row].log_density == run.logdensities[row]
        if backend === :cmdstan
            constant = B._source_fixture_logprior(target.base, zeros(length(raw)))
            @test run.sampler_stats[row].stan_lp + constant ≈ run.logdensities[row] atol = 1e-8
        end
    end
    @test any(abs(B.LogDensityProblems.logdensity(target.base, raw) - run.logdensities[row]) > 1e-5
        for (row, raw) in enumerate(eachrow(run.draws)))

    path = joinpath(directory, "samples.jls")
    B._save_mgmfrm_normalized_prior_samples(path, result)
    loaded = B._load_mgmfrm_normalized_prior_samples(path; expected_identity = identity)
    @test isequal(loaded.record.prior, record.prior)
    @test loaded.record.spec.data.rater_levels == target.base.design.spec.data.rater_levels
    @test isequal(loaded.record.run, run)
    @test isequal(loaded.diagnostics, diagnostics)
    @test loaded.raw_parameter_names == result.raw_parameter_names
    @test loaded.direct_parameter_names == result.direct_parameter_names
    restored = B._MGMFRMNormalizedPriorLogDensity(loaded.record.spec, loaded.record.prior;
        expected_identity = identity)
    @test B._mgmfrm_normalized_prior_identity(restored) == identity
    @test record.prior.source_rater === (target.prior_model === :source ? :judge_b : nothing)
    @test_throws ArgumentError load_fit_cache(path)
    @test_throws ArgumentError B._load_mgmfrm_normalized_prior_samples(path; expected_identity = "wrong")
    original = read(path)
    @test_throws ArgumentError B._save_mgmfrm_normalized_prior_samples(path, result)
    @test read(path) == original
    B._save_mgmfrm_normalized_prior_samples(path, result; overwrite = true)
    @test isequal(B._load_mgmfrm_normalized_prior_samples(path;
        expected_identity = identity).record.run, run)

    # Rehash deliberately malformed records to exercise semantic checks beyond corruption detection.
    rehash(r) = merge(r, (; content_hash = B._mgmfrm_normalized_sample_hash(r)))
    changed_draws = copy(run.draws)
    changed_draws[1, 1] += 0.5
    bad_stat = copy(run.sampler_stats)
    bad_stat[1] = merge(bad_stat[1], (; iteration = 12))
    for bad in (
            merge(record, (; schema = "unknown")),
            merge(record, (; extra = true)),
            merge(record, (; content_hash = "wrong")),
            rehash(merge(record, (; run = merge(run, (; backend = :unknown))))),
            rehash(merge(record, (; run = merge(run, (; initial_logdensity = Inf))))),
            rehash(merge(record, (; run = merge(run, (; controls =
                merge(run.controls, (; gradient_backend = :wrong))))))),
            rehash(merge(record, (; run = merge(run, (; draws = run.draws[1:2, :]))))),
            rehash(merge(record, (; run = merge(run, (; chain_ids = reverse(run.chain_ids)))))),
            rehash(merge(record, (; run = merge(run, (; draws = changed_draws))))),
            rehash(merge(record, (; run = merge(run, (; sampler_stats = bad_stat))))),
            rehash(merge(record, (; prior = merge(record.prior, (; scales =
                merge(record.prior.scales, (; rater_sd = 0.9))))))))
        bad_path = joinpath(directory, "invalid.jls")
        serialize(bad_path, bad)
        @test_throws ArgumentError B._load_mgmfrm_normalized_prior_samples(bad_path; expected_identity = identity)
        @test_throws ArgumentError B._save_mgmfrm_normalized_prior_samples(path,
            merge(result, (; record = bad)); overwrite = true)
        @test read(path) == original
    end
    changed_spec = deepcopy(record.spec)
    changed_spec.data.rater_levels[1] = :changed_id
    bad_path = joinpath(directory, "invalid.jls")
    serialize(bad_path, merge(record, (; spec = changed_spec)))
    @test_throws ArgumentError B._load_mgmfrm_normalized_prior_samples(bad_path; expected_identity = identity)
    return nothing
end

@testset "warmup coverage and event counts stay separate from retained diagnostics" begin
    c = (; warmup = 2, chains = 2, max_depth = 4)
    stats = [B._warmup_stat_row((; is_adapt = true, numerical_error = i == 1,
        tree_depth = i == 1 ? 4 : 1, log_density = i == 1 ? NaN : -1.0), chain, i)
        for chain in 1:2 for i in 1:2]
    rows = B._warmup_diagnostic_rows(stats, c, :advancedhmc)
    @test [r.chain for r in rows] == [1, 2]
    @test all(r -> r.phase === :warmup && r.coverage === :recorded &&
        r.expected_iterations == r.observed_iterations == 2 &&
        r.n_divergences == r.n_max_treedepth == r.n_nonfinite_logdensity == 1, rows)
    unknown = B._warmup_diagnostic_rows(nothing, c, :cmdstan)
    @test all(r -> r.coverage === :not_recorded && ismissing(r.observed_iterations) &&
        ismissing(r.n_divergences) && ismissing(r.n_max_treedepth) &&
        ismissing(r.n_nonfinite_logdensity), unknown)
    for history in (nothing, NamedTuple[])
        absent = B._warmup_diagnostic_rows(history, merge(c, (; warmup = 0)), :advancedhmc)
        @test all(r -> r.coverage === :not_run && r.observed_iterations == 0 &&
            r.n_divergences == r.n_max_treedepth == r.n_nonfinite_logdensity == 0, absent)
    end
    for malformed in (reverse(stats), stats[2:end], vcat(stats, stats),
            [merge(stats[1], (; divergent = missing)); stats[2:end]],
            [merge(stats[1], (; tree_depth = -1)); stats[2:end]])
        @test_throws ArgumentError B._warmup_diagnostic_rows(malformed, c, :advancedhmc)
    end
    @test_throws ArgumentError B._warmup_stat_row((;), 1, 1)
    @test_throws ArgumentError B._warmup_stat_row((; is_adapt = false,
        numerical_error = false, tree_depth = 1, log_density = 0.0), 1, 1)
end

@testset "CmdStan warmup boundary and nonfinite telemetry (synthetic)" begin
    header = "lp__,accept_stat__,stepsize__,treedepth__,n_leapfrog__,divergent__,energy__,beta.1,log_lik.1\n"
    warm = "nan,0,1,4,15,1,inf,nan,nan\n-1,0.5,0.1,1,1,0,1,99,99\n"
    kept = "-0.375,0.9,0.1,1,1,0,1,0.25,-0.125\n"
    marker = "# Adaptation terminated\n"
    mktempdir() do dir
        path = joinpath(dir, "chain.csv")
        evaluated = Float64[]
        evaluate(raw) = (push!(evaluated, only(raw)); (; pointwise = [-0.125], logposterior = -0.375))
        parse() = B._cmdstan_raw_chain_result(path, 1, 1, 3, 1, evaluate; warmup = 2)
        write(path, header * warm * marker * kept)
        result = parse()
        @test evaluated == [0.25] # Warmup values never enter the posterior evaluator.
        @test result.draws == reshape([0.25], 1, 1)
        @test only(result.stats).iteration == 1 && !only(result.stats).is_adapt
        @test result.warmup_stats[1] == (; chain = 3, iteration = 1,
            divergent = true, tree_depth = 4, nonfinite_logdensity = true)
        @test result.warmup_stats[2].iteration == 2
        for bad in (header * warm * kept, header * marker * warm * kept,
                header * warm * marker * marker * kept, header * warm * marker,
                header * replace(warm, ",15,1," => ",15,2,") * marker * kept)
            write(path, bad)
            @test_throws CmdStanError parse()
        end
        write(path, header * warm * marker * kept)
        @test_throws InterruptException B._with_sampler_context(:cmdstan, 3, :output_parse) do
            B._cmdstan_raw_chain_result(path, 1, 1, 3, 1, _ -> throw(InterruptException()); warmup = 2)
        end
    end
end

function check_warmup_invariance(backend)
    for target in targets
        mktempdir() do directory
            fits = [B._mgmfrm_normalized_prior_sample(target; backend, controls..., record_warmup,
                (backend === :cmdstan ? (; cmdstan_cache_dir = joinpath(directory, "compile-$record_warmup")) : (;))...)
                for record_warmup in (false, true)]
            old, recorded = fits
            @test old.record.schema == "bayesianmgmfrm.normalized_fixed_q_samples.v1"
            @test recorded.record.schema == "bayesianmgmfrm.normalized_fixed_q_samples.v2"
            @test old.record.target_identity == recorded.record.target_identity
            for field in (:draws, :logdensities, :chain_ids, :iterations,
                    :chain_acceptance, :sampler_stats, :sampler_rows)
                @test isequal(getproperty(old.record.run, field), getproperty(recorded.record.run, field))
            end
            @test isequal(old.diagnostics, recorded.diagnostics)
            @test all(r -> r.coverage === :not_recorded && ismissing(r.n_divergences), old.warmup_diagnostics)
            @test all(r -> r.coverage === :recorded && r.observed_iterations == controls.warmup,
                recorded.warmup_diagnostics)
            @test length(recorded.record.run.warmup_stats) == controls.warmup * controls.chains
            for (i, result) in enumerate(fits)
                path = joinpath(directory, "sample-$i.jls")
                B._save_mgmfrm_normalized_prior_samples(path, result)
                restored = B._load_mgmfrm_normalized_prior_samples(path;
                    expected_identity = result.record.target_identity)
                @test isequal(restored.record.run, result.record.run)
                @test isequal(restored.warmup_diagnostics, result.warmup_diagnostics)
            end
            for changed in (merge(recorded.record, (; schema = old.record.schema)),
                    merge(recorded.record, (; run = merge(recorded.record.run, (; warmup_stats = nothing)))),
                    merge(recorded.record, (; run = merge(recorded.record.run,
                        (; warmup_stats = recorded.record.run.warmup_stats[2:end])))))
                bad = merge(changed, (; content_hash = B._mgmfrm_normalized_sample_hash(changed)))
                path = joinpath(directory, "sample-2.jls")
                bytes = read(path)
                @test_throws ArgumentError B._save_mgmfrm_normalized_prior_samples(path,
                    merge(recorded, (; record = bad)); overwrite = true)
                @test read(path) == bytes
            end
        end
    end
    mktempdir() do directory
        zero = B._mgmfrm_normalized_prior_sample(first(targets); backend,
            merge(controls, (; warmup = 0))...,
            (backend === :cmdstan ? (; cmdstan_cache_dir = joinpath(directory, "compile")) : (;))...)
        @test isempty(zero.record.run.warmup_stats)
        @test all(r -> r.coverage === :not_run && r.observed_iterations == 0, zero.warmup_diagnostics)
    end
end

@testset "normalized-prior Julia warmup recording preserves seeded retained output" begin
    check_warmup_invariance(:advancedhmc)
end

@testset "normalized-prior Julia NUTS and saved samples (operability only)" begin
    for target in targets
        mktempdir(directory -> check_samples(target, :advancedhmc, directory))
    end
end

if test_flag("BAYESIANMGMFRM_CMDSTAN_TESTS")
    @testset "normalized-prior CmdStan warmup recording preserves seeded retained output" begin
        check_warmup_invariance(:cmdstan)
    end
    @testset "normalized-prior CmdStan NUTS and saved samples (operability only)" begin
        for target in targets
            mktempdir(directory -> check_samples(target, :cmdstan, directory))
        end
    end
end

end
