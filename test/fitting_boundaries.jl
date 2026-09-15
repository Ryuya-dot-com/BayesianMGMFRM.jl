using Test
using Random
using BayesianMGMFRM
import Serialization

@testset "Float64 prior and initial-value boundaries (no fitting)" begin
    for constructor in (MFRMPrior, BayesianMGMFRM.Experimental.GeneralizedPrior,
            BayesianMGMFRM._SourceFixturePrior), name in fieldnames(constructor)
        for value in (big"1e400", big"1e-400", Inf, NaN, 0, -1)
            @test_throws ArgumentError constructor(; name => value)
        end
        for value in (big"1.25", 1 // 2, Float32(0.5),
                BigFloat(floatmax(Float64)), BigFloat(nextfloat(0.0)))
            prior = constructor(; name => value)
            @test getproperty(prior, name) === Float64(value)
        end
    end

    data = FacetData((; person = [1, 1, 1, 1, 2, 2, 2, 2],
            item = [1, 2, 3, 4, 1, 2, 3, 4], rater = [1, 2, 1, 2, 2, 1, 2, 1],
            score = [0, 1, 2, 0, 2, 1, 0, 2]);
        person = :person, item = :item, rater = :rater, score = :score)
    spec = mfrm_spec(data)
    design = getdesign(spec)
    gm = mfrm_spec(data; family = :gmfrm, thresholds = :partial_credit,
        discrimination = :rater)
    mgm = mfrm_spec(data; family = :mgmfrm, dimensions = 2,
        thresholds = :partial_credit, q_matrix = Bool[1 0; 1 0; 0 1; 0 1])
    gm_target = BayesianMGMFRM._gmfrm_promotion_candidate_logdensity(gm)
    mgm_target = BayesianMGMFRM._mgmfrm_guarded_local_fit_logdensity(mgm)
    correlated = BayesianMGMFRM._mgmfrm_free_latent_correlation_2d_logdensity(mgm_target)
    for object in (spec, design, MFRMLogDensity(spec),
            BayesianMGMFRM._source_fixture_logdensity(gm),
            BayesianMGMFRM._source_fixture_logdensity(mgm),
            gm_target, mgm_target, correlated)
        for value in (big"1e400", -big"1e400", Inf, NaN)
            @test_throws ArgumentError initial_params(object; value)
        end
        @test all(isfinite, initial_params(object; value = big"0.25"))
        @test eltype(initial_params(object; value = 1 // 4)) === Float64
    end
    for zrho in (big"1e400", -big"1e400", Inf, NaN)
        @test_throws ArgumentError initial_params(correlated; zrho)
    end
    @test last(initial_params(correlated; zrho = big"0.25")) === 0.25
    for (object, initialize) in (
            (design, BayesianMGMFRM._fit_initial_params),
            (gm_target, BayesianMGMFRM._experimental_gmfrm_initial),
            (mgm_target, BayesianMGMFRM._guarded_mgmfrm_initial))
        bad = BigFloat.(initial_params(object))
        bad[1] = big"1e400"
        @test_throws ArgumentError initialize(object, bad)
    end
end

# Inject real serialization failures without adding production test hooks.
struct CacheSerializationFailure end
Serialization.serialize(::Serialization.AbstractSerializer, ::CacheSerializationFailure) =
    error("injected cache serialization failure")

struct CacheConcurrentDestination
    path::String
    directory::Bool
end
function Serialization.serialize(serializer::Serialization.AbstractSerializer,
        value::CacheConcurrentDestination)
    if value.directory
        mkdir(value.path)
        write(joinpath(value.path, "keep.txt"), "existing directory")
    else
        write(value.path, "concurrent writer")
    end
    return Serialization.serialize(serializer, nothing)
end

@testset "fit cache publication preserves existing results (no fitting)" begin
    data = FacetData((; person = [1, 1, 2, 2], item = [1, 2, 1, 2],
            rater = [1, 2, 2, 1], score = [0, 1, 2, 0]);
        person = :person, item = :item, rater = :rater, score = :score)
    design = getdesign(mfrm_spec(data))
    prior = MFRMPrior()
    # Deterministic I/O fixture, not estimated posterior draws.
    draws = zeros(4, length(design.parameter_names))
    fit = MFRMFit(design, prior, draws,
        [logposterior(design, row, prior) for row in eachrow(draws)],
        1.0, ones(Int, 4), collect(1:4), [1.0], :fixture, :fixture, 0, 0.1)
    artifact = (; schema = "cache_io_test", parameter_names = design.parameter_names)
    mktempdir() do directory
        path = joinpath(directory, "fit.jls")
        save_fit_cache(path, fit; artifact, cache_key = "original")
        original = read(path)
        @test_throws ArgumentError save_fit_cache(path, fit; artifact)
        failing = merge(artifact, (; failure = CacheSerializationFailure()))
        @test_throws ErrorException save_fit_cache(path, fit;
            artifact = failing, overwrite = true)
        @test read(path) == original
        loaded = load_fit_cache(path; expected_cache_key = "original")
        @test loaded.draws == fit.draws
        @test loaded.log_posterior == fit.log_posterior
        @test loaded.chain_ids == fit.chain_ids
        @test readdir(directory) == ["fit.jls"]

        absent = joinpath(directory, "failed.jls")
        @test_throws ErrorException save_fit_cache(absent, fit; artifact = failing)
        @test !ispath(absent)
        @test readdir(directory) == ["fit.jls"]

        save_fit_cache(path, fit; artifact, overwrite = true, cache_key = "replacement")
        @test load_fit_cache(path; expected_cache_key = "replacement").draws == fit.draws
        @test_throws ArgumentError load_fit_cache(path; expected_cache_key = "original")

        raced = joinpath(directory, "race.jls")
        collision = merge(artifact, (; race = CacheConcurrentDestination(raced, false)))
        @test_throws Base.IOError save_fit_cache(raced, fit; artifact = collision)
        @test read(raced, String) == "concurrent writer"
        @test sort(readdir(directory)) == ["fit.jls", "race.jls"]

        blocked = joinpath(directory, "directory.jls")
        collision = merge(artifact, (; race = CacheConcurrentDestination(blocked, true)))
        @test_throws Base.IOError save_fit_cache(blocked, fit; artifact = collision, overwrite = true)
        @test read(joinpath(blocked, "keep.txt"), String) == "existing directory"
        @test sort(readdir(directory)) == ["directory.jls", "fit.jls", "race.jls"]

        # Windows symlink creation may require privileges unavailable in ordinary CI.
        if !Sys.iswindows()
            link = joinpath(directory, "link.jls")
            symlink(path, link)
            @test_throws ArgumentError save_fit_cache(link, fit; artifact)
            target_bytes = read(path)
            save_fit_cache(link, fit; artifact, overwrite = true, cache_key = "link")
            @test !islink(link)
            @test load_fit_cache(link; expected_cache_key = "link").draws == fit.draws
            @test read(path) == target_bytes

            dangling = joinpath(directory, "dangling.jls")
            symlink(absent, dangling)
            @test_throws ArgumentError save_fit_cache(dangling, fit; artifact)
            @test islink(dangling) && !ispath(absent)
        end
    end
end

@testset "sampler controls are validated before execution and cache lookup" begin
    data = FacetData((; person = [1, 1, 1, 1, 2, 2, 2, 2],
            item = [1, 2, 3, 4, 1, 2, 3, 4], rater = [1, 2, 1, 2, 2, 1, 2, 1],
            score = [0, 1, 2, 0, 2, 1, 0, 2]);
        person = :person, item = :item, rater = :rater, score = :score)
    specs = (mfrm_spec(data),
        mfrm_spec(data; family = :gmfrm, thresholds = :partial_credit,
            discrimination = :rater),
        mfrm_spec(data; family = :mgmfrm, dimensions = 2,
            thresholds = :partial_credit, q_matrix = Bool[1 0; 1 0; 0 1; 0 1]))
    # Both numbers satisfy 0 < x < 1 before conversion, but round to 0 and 1.
    bad_controls = (
        :step_size => (big"1e400", big"1e-400", Inf, NaN, 0.0, -1.0),
        :target_accept => (big"1e-400", 1 - eps(BigFloat), Inf, NaN, 0.0, 1.0),
        :max_energy_error => (big"1e400", big"1e-400", Inf, NaN, 0.0, -1.0),
        :init_jitter => (big"1e400", Inf, NaN, -1.0, -big"1e-400"),
        :ndraws => (0,), :warmup => (-1,), :chains => (0,), :max_depth => (0,))
    function rejects_control(operation, name)
        error = try
            operation()
            nothing
        catch err
            err
        end
        @test error isa ArgumentError
        @test error isa ArgumentError && occursin(String(name), sprint(showerror, error))
    end
    mktempdir() do directory
        for spec in specs
            experimental = spec.family !== :mfrm
            backends = experimental ? (:advancedhmc, :cmdstan) :
                (:julia, :advancedhmc, :turing, :cmdstan)
            for backend in backends
                extra = backend === :cmdstan ?
                    (; cmdstan_path = joinpath(directory, "missing-cmdstan"),
                        cmdstan_cache_dir = joinpath(directory, "compile-cache")) : (;)
                for (name, values) in bad_controls
                    backend === :julia && name in
                        (:target_accept, :max_energy_error, :init_jitter, :max_depth) && continue
                    for value in values
                        options = merge((; ndraws = 1, warmup = 0, chains = 1,
                            seed = 19, max_depth = 1), (; name => value))
                        rejects_control(() -> fit(spec;
                            experimental, backend, options..., extra...), name)
                        if backend !== :cmdstan
                            rejects_control(() -> fit_cache_key(spec;
                                experimental, backend, options...), name)
                        end
                    end
                end
                if backend !== :cmdstan
                    options = (; experimental, backend, ndraws = 1, warmup = 0,
                        chains = 1, seed = 19)
                    @test fit_cache_key(spec; options..., step_size = 1 // 8,
                        target_accept = big"0.75", max_energy_error = big"1000",
                        init_jitter = big"0.125") ==
                        fit_cache_key(spec; options..., step_size = 0.125,
                            target_accept = 0.75, max_energy_error = 1000.0,
                            init_jitter = 0.125)
                end
            end
        end
        # Reject a finite vector whose log posterior is non-finite before CmdStan
        # discovery/compilation, matching the Julia initialization failure policy.
        spec = first(specs)
        bad_initial = fill(1e300, length(initial_params(spec)))
        for backend in (:julia, :advancedhmc, :turing, :cmdstan)
            extra = backend === :cmdstan ?
                (; cmdstan_path = joinpath(directory, "missing-cmdstan")) : (;)
            rejects_control(() -> fit(spec; backend, init = bad_initial,
                ndraws = 1, warmup = 0, seed = 19, extra...), :initial)
        end
        @test isempty(readdir(directory))
    end

    # The research-only sampler shares the guards without being promoted to fit.
    correlated = BayesianMGMFRM._mgmfrm_free_latent_correlation_2d_logdensity(last(specs))
    for (name, values) in bad_controls, value in values
        options = merge((; ndraws = 1, warmup = 0, chains = 1, seed = 19), (; name => value))
        rejects_control(() -> BayesianMGMFRM._mgmfrm_free_latent_correlation_2d_sample_bundle(
            correlated; options...), name)
    end
    rejects_control(() -> BayesianMGMFRM._mgmfrm_free_latent_correlation_2d_sample_bundle(
        correlated; ndraws = 1, warmup = 0, chains = 1, init_jitter = big"1e-400",
        chain_initials = zeros(1, length(initial_params(correlated)))), :init_jitter)
end

@testset "valid sampler controls preserve draw and summary correspondence (tiny fitting)" begin
    data = FacetData((; person = [1, 1, 1, 1, 2, 2, 2, 2],
            item = [1, 2, 3, 4, 1, 2, 3, 4], rater = [1, 2, 1, 2, 2, 1, 2, 1],
            score = [0, 1, 2, 0, 2, 1, 0, 2]);
        person = :person, item = :item, rater = :rater, score = :score)
    specs = (mfrm_spec(data),
        mfrm_spec(data; family = :gmfrm, thresholds = :partial_credit,
            discrimination = :rater),
        mfrm_spec(data; family = :mgmfrm, dimensions = 2,
            thresholds = :partial_credit, q_matrix = Bool[1 0; 1 0; 0 1; 0 1]))
    # Only exercise plumbing: this draw budget cannot assess inference quality.
    for spec in specs
        experimental = spec.family !== :mfrm
        for backend in (experimental ? (:advancedhmc,) : (:julia, :advancedhmc, :turing))
            result = fit(spec; experimental, backend, ndraws = 4, warmup = 2,
                chains = 2, seed = 29, step_size = big"0.03", max_depth = 2,
                target_accept = big"0.75", max_energy_error = big"1000",
                init_jitter = big"0.01", metric = :unit)
            @test result.sampler_controls.step_size === 0.03
            @test result.sampler_controls.init_jitter === (backend === :julia ? 0.0 : 0.01)
            if backend !== :julia
                @test result.sampler_controls.target_accept === 0.75
                @test result.sampler_controls.max_energy_error === 1000.0
            end
            @test result.chain_ids == repeat(1:2; inner = 4)
            @test result.iterations == repeat(1:4, 2)
            @test BayesianMGMFRM._fit_draws_per_chain(result) == 4
            @test [row.chain for row in result.sampler_stats] == result.chain_ids
            @test [row.iteration for row in result.sampler_stats] == result.iterations
            @test [row.log_density for row in result.sampler_stats] ≈ result.log_posterior
            @test all(isfinite, result.draws)
            target = spec.family === :mfrm ? MFRMLogDensity(spec) :
                BayesianMGMFRM._source_fixture_logdensity(spec)
            expected_lp = [BayesianMGMFRM.LogDensityProblems.logdensity(target, row)
                for row in eachrow(result.draws)]
            @test result.log_posterior ≈ expected_lp
            summary = posterior_summary(result)
            @test [row.mean for row in summary] ≈ vec(sum(result.draws; dims = 1)) / 8
            expected_names = experimental ? result.diagnostic_surface.raw_parameter_names :
                result.design.parameter_names
            @test [row.parameter for row in summary] == expected_names
            if experimental
                direct_summary = BayesianMGMFRM.direct_posterior_summary(result)
                @test [row.mean for row in direct_summary] ≈
                    vec(sum(result.direct_draws; dims = 1)) / 8
                @test [row.parameter for row in direct_summary] ==
                    result.diagnostic_surface.direct_parameter_names
            end
            malformed = deepcopy(result)
            malformed.chain_ids[1] = 2
            @test_throws ArgumentError BayesianMGMFRM._fit_draws_per_chain(malformed)
            malformed.chain_ids[1] = 1
            malformed.iterations[1] = 2
            @test_throws ArgumentError BayesianMGMFRM._fit_draws_per_chain(malformed)
        end
    end
end

@testset "non-finite random-walk proposals remain rejected and visible" begin
    data = FacetData((; person = [1, 1, 2, 2], item = [1, 2, 1, 2],
            rater = [1, 2, 2, 1], score = [0, 1, 2, 0]);
        person = :person, item = :item, rater = :rater, score = :score)
    spec = mfrm_spec(data)
    # A finite step can overflow proposals or their log density during sampling.
    rng = MersenneTwister(31)
    result = fit(spec; rng, step_size = floatmax(Float64),
        ndraws = 3, warmup = 1, chains = 2)
    @test result.draws == zeros(6, length(initial_params(spec)))
    @test all(isfinite, result.log_posterior)
    @test all(row -> row.nonfinite_proposal && row.numerical_error && !row.is_accept,
        result.sampler_stats)
    @test result.acceptance_rate == 0.0
    @test result.chain_ids == [1, 1, 1, 2, 2, 2]
    @test result.iterations == [1, 2, 3, 1, 2, 3]
    rows = sampler_diagnostics(result)
    @test [row.n_nonfinite_proposals for row in rows] == [3, 3]
    @test all(row -> row.n_divergences == 0 && row.flag === :nonfinite_proposals, rows)
    surface = diagnostics(result; view = :public)
    @test surface.summary.n_nonfinite_proposals == 6
    @test surface.summary.n_divergences == 0
    @test surface.summary.n_sampler_warnings == 2
    @test surface.summary.flag === :sampler_warning
    corrupted = deepcopy(result)
    corrupted.log_posterior[1] = NaN
    @test first(sampler_diagnostics(corrupted)).flag === :nonfinite_log_posterior
    # Invalid proposals must still consume one acceptance uniform per iteration.
    reference_rng = MersenneTwister(31)
    for _ in 1:8
        for _ in axes(result.draws, 2)
            randn(reference_rng)
        end
        rand(reference_rng)
    end
    @test rand(rng) == rand(reference_rng)

    ordinary = fit(spec; step_size = 100.0, ndraws = 3, warmup = 1, chains = 2, seed = 31)
    @test ordinary.acceptance_rate == 0.0
    @test all(row -> !row.nonfinite_proposal && !row.numerical_error, ordinary.sampler_stats)
    @test all(row -> row.n_nonfinite_proposals == 0 && row.flag === :zero_acceptance,
        sampler_diagnostics(ordinary))

    # Old caches did not record this distinction; absence must remain unknown.
    legacy = deepcopy(result)
    for i in eachindex(legacy.sampler_stats)
        row = legacy.sampler_stats[i]
        legacy.sampler_stats[i] = merge(
            Base.structdiff(row, (; nonfinite_proposal = row.nonfinite_proposal)),
            (; numerical_error = false))
    end
    @test all(row -> ismissing(row.n_nonfinite_proposals), sampler_diagnostics(legacy))
    @test ismissing(diagnostics(legacy).summary.n_nonfinite_proposals)
    partial = deepcopy(result)
    partial.sampler_stats[1] = legacy.sampler_stats[1]
    @test ismissing(sampler_diagnostics(partial)[1].n_nonfinite_proposals)
    @test sampler_diagnostics(partial)[2].n_nonfinite_proposals == 3
    @test ismissing(diagnostics(partial).summary.n_nonfinite_proposals)
    mktempdir() do directory
        for (name, fitted) in (("current", result), ("legacy", legacy))
            path = joinpath(directory, "$name.jls")
            save_fit_cache(path, fitted; artifact = (; schema = "transition_check"))
            @test isequal(sampler_diagnostics(load_fit_cache(path)), sampler_diagnostics(fitted))
        end
    end
end

@testset "retained sampler output is checked with chain and draw context" begin
    draws = zeros(2, 2)
    logps = zeros(2)
    stat = (; chain = 2, iteration = 3, log_density = -2.0, numerical_error = true)
    # A divergent transition may legitimately retain the last finite state.
    @test isnothing(BayesianMGMFRM._store_sampler_draw!(draws, logps, [1.0, -1.0], stat, 1))
    @test draws[1, :] == [1.0, -1.0]
    @test logps[1] == -2.0
    for (values, density, message) in (([1.0], -2.0, "parameters"),
            ([NaN, 1.0], -2.0, "non-finite parameters"),
            ([Inf, 1.0], -2.0, "non-finite parameters"),
            ([big"1e400", 1.0], -2.0, "non-finite parameters"),
            ([1.0, -1.0], Inf, "non-finite log density"),
            ([1.0, -1.0], -Inf, "non-finite log density"),
            ([1.0, -1.0], NaN, "non-finite log density"),
            ([1.0, -1.0], big"1e400", "non-finite log density"))
        error = try
            BayesianMGMFRM._store_sampler_draw!(draws, logps, values,
                merge(stat, (; log_density = density)), 2)
            nothing
        catch err
            err
        end
        @test error isa ArgumentError
        @test error isa ArgumentError && occursin("chain 2 retained draw 3", sprint(showerror, error))
        @test error isa ArgumentError && occursin(message, sprint(showerror, error))
        @test draws[1, :] == [1.0, -1.0] && logps[1] == -2.0
    end
end

# Own-type fault injection exercises the real adapters without production hooks.
module FittingExceptionChecks
using Test, Random, BayesianMGMFRM
import LogDensityProblems, JSON3
const B = BayesianMGMFRM
capture(operation) = try operation() catch err; err end

struct FailingTarget
    cause::Exception
end
LogDensityProblems.dimension(::FailingTarget) = 1
LogDensityProblems.capabilities(::Type{FailingTarget}) = LogDensityProblems.LogDensityOrder{1}()
LogDensityProblems.logdensity(target::FailingTarget, x) = throw(target.cause)
LogDensityProblems.logdensity_and_gradient(target::FailingTarget, x) = throw(target.cause)
struct FailingJSON
    cause::Exception
end
JSON3.write(io::IO, value::FailingJSON) = throw(value.cause)
struct FailingFinite
    cause::Exception
end
Base.isfinite(value::FailingFinite) = throw(value.cause)

mutable struct FailingRNG <: AbstractRNG
    rng::MersenneTwister
    normals_left::Int
    cause::Exception
    failures::Int
end
function Random.randn(rng::FailingRNG)
    if rng.normals_left == 0
        rng.failures += 1
        throw(rng.cause)
    end
    rng.normals_left -= 1
    return randn(rng.rng)
end
Random.rand(rng::FailingRNG) = rand(rng.rng)
Random.rand(rng::FailingRNG, ::Type{UInt64}) = rand(rng.rng, UInt64)
Random.rand(rng::FailingRNG, ::Type{Bool}) = rand(rng.rng, Bool)
Random.rand(rng::FailingRNG, ::Type{Float64}) = rand(rng.rng, Float64)
Random.randexp(rng::FailingRNG) = randexp(rng.rng)
Random.randn(rng::FailingRNG, ::Type{Float64}, n::Int) = [randn(rng) for _ in 1:n]

# Test-owned dispatch keeps the real seeded cache/fit path while injecting RNG faults.
# Production RNG methods and cache replayability requirements are unchanged.
function B._fit_rng(rng::FailingRNG, seed::Integer)
    seeded, controls = B._fit_rng(Random.default_rng(), seed)
    rng.rng = seeded
    return rng, controls
end

@testset "fatal signals escape fitting adapters and report capture" begin
    data = FacetData((; person = [1, 1, 2, 2], item = [1, 2, 1, 2],
            rater = [1, 2, 2, 1], score = [0, 1, 2, 0]);
        person = :person, item = :item, rater = :rater, score = :score)
    spec = mfrm_spec(data)
    design = getdesign(spec)
    nparams = length(initial_params(spec))
    mktempdir() do directory
        for cause in (InterruptException(), OutOfMemoryError(), StackOverflowError())
            for ad in (:analytic, :ForwardDiff)
                @test capture(() -> B._logdensity_gradient_target(
                    FailingTarget(cause), [0.0], ad)) === cause
            end
            @test capture(() -> B._cmdstan_write_json(joinpath(directory, "data.json"),
                FailingJSON(cause), :data_write)) === cause
            @test capture(() -> B._check_parameter_vector(design,
                fill(FailingFinite(cause), nparams))) === cause
            @test capture(() -> B._check_source_fixture_raw_vector(
                (; blueprint = (; n_parameters = nparams)),
                fill(FailingFinite(cause), nparams))) === cause
            for policy in (:capture, :throw)
                @test capture(() -> B._fit_report_section(() -> throw(cause), policy)) === cause
            end
            @test capture(() -> B._with_sampler_context(
                () -> throw(cause), :cmdstan, 2, :sampling)) === cause
            @test B._mgmfrm_stress_fatal_exception(cause)
        end
        ordinary = ErrorException("injected adapter failure")
        gradient_error = capture(() -> B._logdensity_gradient_target(
            FailingTarget(ordinary), [0.0], :analytic))
        @test gradient_error isa ArgumentError
        @test occursin(ordinary.msg, sprint(showerror, gradient_error))
        json_error = capture(() -> B._cmdstan_write_json(joinpath(directory, "data.json"),
            FailingJSON(ordinary), :data_write))
        @test json_error isa CmdStanError
        @test json_error.stage === :data_write && json_error.reason === :unexpected_error
        report = B._fit_report_section(() -> throw(ordinary), :capture)
        @test report.status === :error && report.exception === :ErrorException
        @test report.message == ordinary.msg
        @test capture(() -> B._fit_report_section(() -> throw(ordinary), :throw)) === ordinary
        @test !B._mgmfrm_stress_fatal_exception(ordinary)
    end

    # A complete first RW chain followed by a failure must not return a partial fit or retry.
    for cause in (ErrorException("injected sampler failure"), InterruptException())
        rng = FailingRNG(MersenneTwister(31), 2 * nparams, cause, 0)
        failure = capture(() -> fit(spec; rng, ndraws = 2, warmup = 0, chains = 3))
        @test rng.failures == 1
        if cause isa InterruptException
            @test failure === cause
        else
            @test failure isa B._SamplerError
            @test (failure.backend, failure.chain, failure.phase) == (:julia, 2, :sampling)
            @test failure.cause.ex === cause
            @test !isempty(failure.cause.processed_bt)
            @test occursin("julia chain 2 failed during sampling", sprint(showerror, failure))
            @test occursin("randn", sprint(showerror, failure))
        end
    end
    # The library samplers receive the same RNG fault after preflight, without monkeypatching them.
    for backend in (:advancedhmc, :turing), cause in (
            ErrorException("injected NUTS RNG failure"), InterruptException())
        rng = FailingRNG(MersenneTwister(31), 0, cause, 0)
        failure = capture(() -> fit(spec; backend, rng, ndraws = 1, warmup = 0, chains = 2))
        @test rng.failures == 1
        if cause isa InterruptException
            @test failure === cause
        else
            @test failure isa B._SamplerError
            @test (failure.backend, failure.chain, failure.phase) == (backend, 1, :sampling)
            @test failure.cause.ex === cause
            @test !isempty(failure.cause.processed_bt)
        end
    end
end

@testset "CmdStan chain context preserves stage and reason" begin
    # Synthetic executable only: exercise command and parser wiring, not Stan inference.
    if Sys.isunix()
        mktempdir() do directory
            executable = joinpath(directory, "synthetic-command")
            write(executable, "#!/bin/sh\nexit 0\n")
            chmod(executable, 0o700)
            expected_sha256 = B._cmdstan_executable_sha256(executable, :sampling)
            for cause in (CmdStanError(:output_parse, :header_missing, "injected missing header"),
                    ErrorException("injected parser failure"), InterruptException())
                visited = Int[]
                parser = function (_, chain, _)
                    push!(visited, chain)
                    chain == 2 && throw(cause)
                    return (; draws = zeros(1, 1), logps = [-1.0],
                        stats = [(; acceptance_rate = 0.5)])
                end
                failure = capture(() -> B._cmdstan_sample_chains(executable, (;), [0.0],
                    MersenneTwister(31), _ -> -1.0, parser;
                    expected_sha256, ndraws = 1, warmup = 0, chains = 3, step_size = 0.05,
                    target_accept = 0.8, max_depth = 2, metric = "unit_e", init_jitter = 0.0,
                    progress = false))
                @test visited == [1, 2]
                if cause isa CmdStanError
                    @test failure isa CmdStanError
                    @test (failure.stage, failure.reason) == (cause.stage, cause.reason)
                    @test occursin("chain 2 (output_parse)", failure.detail)
                    @test occursin(cause.detail, failure.detail)
                elseif cause isa InterruptException
                    @test failure === cause
                else
                    @test failure isa B._SamplerError
                    @test (failure.backend, failure.chain, failure.phase) == (:cmdstan, 2, :output_parse)
                    @test failure.cause.ex === cause
                    @test !isempty(failure.cause.processed_bt)
                end
            end
            # Reject malformed retained output before broadcasting can hide a shape error.
            for broken in ((; draws = zeros(2, 1), logps = [-1.0], stats = [(; acceptance_rate = 0.5)]),
                    (; draws = zeros(1, 2), logps = [-1.0], stats = [(; acceptance_rate = 0.5)]),
                    (; draws = zeros(1, 1), logps = [-1.0, -2.0], stats = [(; acceptance_rate = 0.5)]),
                    (; draws = zeros(1, 1), logps = [-1.0], stats = NamedTuple[]),
                    (; draws = fill(big"1e400", 1, 1), logps = [-1.0], stats = [(; acceptance_rate = 0.5)]),
                    (; draws = zeros(1, 1), logps = [NaN], stats = [(; acceptance_rate = 0.5)]))
                visited = Int[]
                parser = function (_, chain, _)
                    push!(visited, chain)
                    return chain == 2 ? broken :
                        (; draws = zeros(1, 1), logps = [-1.0], stats = [(; acceptance_rate = 0.5)])
                end
                failure = capture(() -> B._cmdstan_sample_chains(executable, (;), [0.0],
                    MersenneTwister(31), _ -> -1.0, parser;
                    expected_sha256, ndraws = 1, warmup = 0, chains = 3, step_size = 0.05,
                    target_accept = 0.8, max_depth = 2, metric = "unit_e", init_jitter = 0.0,
                    progress = false))
                @test visited == [1, 2]
                @test failure isa ArgumentError
                @test occursin("cmdstan chain 2 failed during output_validation", sprint(showerror, failure))
            end
            for cause in (ErrorException("injected initialization failure"), InterruptException())
                initialized = Ref(0)
                parsed = Int[]
                evaluate = function (_)
                    initialized[] += 1
                    initialized[] == 2 && throw(cause)
                    -1.0
                end
                parser = function (_, chain, _)
                    push!(parsed, chain)
                    (; draws = zeros(1, 1), logps = [-1.0], stats = [(; acceptance_rate = 0.5)])
                end
                failure = capture(() -> B._cmdstan_sample_chains(executable, (;), [0.0],
                    MersenneTwister(31), evaluate, parser;
                    expected_sha256, ndraws = 1, warmup = 0, chains = 3, step_size = 0.05,
                    target_accept = 0.8, max_depth = 2, metric = "unit_e", init_jitter = 0.0,
                    progress = false))
                @test initialized[] == 2 && parsed == [1]
                if cause isa InterruptException
                    @test failure === cause
                else
                    @test failure isa B._SamplerError
                    @test (failure.backend, failure.chain, failure.phase) == (:cmdstan, 2, :initialization)
                    @test failure.cause.ex === cause
                end
            end
            # A real command failure after the first chain's output was accepted.
            write(executable, raw"""#!/bin/sh
            for argument do
                case "$argument" in
                    id=*) echo "$argument" >> "$0.visits"
                          [ "$argument" = "id=2" ] && exit 7 ;;
                esac
            done
            exit 0
            """)
            parsed = Int[]
            parser = function (_, chain, _)
                push!(parsed, chain)
                (; draws = zeros(1, 1), logps = [-1.0], stats = [(; acceptance_rate = 0.5)])
            end
            failure = capture(() -> B._cmdstan_sample_chains(executable, (;), [0.0],
                MersenneTwister(31), _ -> -1.0, parser;
                expected_sha256 = B._cmdstan_executable_sha256(executable, :sampling),
                ndraws = 1, warmup = 2, chains = 3, step_size = 0.05,
                target_accept = 0.8, max_depth = 2, metric = "unit_e", init_jitter = 0.0,
                progress = false))
            @test readlines(executable * ".visits") == ["id=1", "id=2"]
            @test parsed == [1]
            @test failure isa CmdStanError
            @test (failure.stage, failure.reason) == (:sampling, :command_failed)
            @test occursin("chain 2 (sampling)", failure.detail)

            write(executable, "#!/bin/sh\nexit 7\n")
            for show_output in (false, true)
                failure = capture(() -> B._with_sampler_context(:cmdstan, 2, :sampling) do
                    B._cmdstan_run(`$executable`, :sampling; show_output)
                end)
                @test failure isa CmdStanError
                @test (failure.stage, failure.reason) == (:sampling, :command_failed)
                @test occursin("chain 2 (sampling)", failure.detail)
            end
        end
    end
end
@testset "initialization and output-validation context" begin
    data = FacetData((; person = [1, 1, 1, 1, 2, 2, 2, 2],
            item = [1, 2, 3, 4, 1, 2, 3, 4], rater = [1, 2, 1, 2, 2, 1, 2, 1],
            score = [0, 1, 2, 0, 2, 1, 0, 2]);
        person = :person, item = :item, rater = :rater, score = :score)
    stable = mfrm_spec(data)
    gm = mfrm_spec(data; family = :gmfrm, thresholds = :partial_credit, discrimination = :rater)
    mgm = mfrm_spec(data; family = :mgmfrm, dimensions = 2,
        thresholds = :partial_credit, q_matrix = Bool[1 0; 1 0; 0 1; 0 1])
    correlated = B._mgmfrm_free_latent_correlation_2d_logdensity(mgm)
    for (backend, run) in (
            (:advancedhmc, rng -> fit(stable; backend = :advancedhmc, rng,
                init_jitter = 0.1, ndraws = 1, warmup = 0, chains = 2)),
            (:turing, rng -> fit(stable; backend = :turing, rng,
                init_jitter = 0.1, ndraws = 1, warmup = 0, chains = 2)),
            (:advancedhmc, rng -> fit(gm; experimental = true, rng,
                init_jitter = 0.1, ndraws = 1, warmup = 0, chains = 2)),
            (:advancedhmc, rng -> fit(mgm; experimental = true, rng,
                init_jitter = 0.1, ndraws = 1, warmup = 0, chains = 2)),
            (:advancedhmc, rng -> B._mgmfrm_free_latent_correlation_2d_sample_bundle(correlated;
                rng, init_jitter = 0.1, ndraws = 1, warmup = 0, chains = 2)))
        for cause in (ErrorException("injected initial jitter failure"), InterruptException())
            rng = FailingRNG(MersenneTwister(31), 0, cause, 0)
            failure = capture(() -> run(rng))
            @test rng.failures == 1
            if cause isa InterruptException
                @test failure === cause
            else
                @test failure isa B._SamplerError
                @test (failure.backend, failure.chain, failure.phase) == (backend, 1, :initialization)
                @test failure.cause.ex === cause
                @test !isempty(failure.cause.processed_bt)
            end
        end
    end
    # Existing validation types survive added context (including unsupported gradients).
    failure = capture(() -> fit(stable; backend = :advancedhmc, ad_backend = :analytic,
        ndraws = 1, warmup = 0))
    @test failure isa ArgumentError
    @test occursin("chain 1 failed during initialization", sprint(showerror, failure))
    @test occursin("ad_backend", sprint(showerror, failure))
    for backend in (:turing, :advancedhmc)
        failure = capture(() -> B._with_sampler_context(backend, 2, :output_validation) do
            B._store_sampler_draw!(zeros(1, 2), zeros(1), [NaN, 1.0],
                (; chain = 2, iteration = 3, log_density = -1.0), 1)
        end)
        @test failure isa ArgumentError
        @test occursin("chain 2 failed during output_validation", sprint(showerror, failure))
        @test occursin("retained draw 3", sprint(showerror, failure))
        # A malformed library statistic keeps its original exception and backtrace.
        failure = capture(() -> B._with_sampler_context(backend, 2, :output_validation) do
            B._advancedhmc_stat_row((; n_steps = missing), 2, 3)
        end)
        @test failure isa B._SamplerError
        @test failure.phase === :output_validation && failure.chain == 2
        @test failure.cause.ex isa MethodError
        @test !isempty(failure.cause.processed_bt)
    end
end
@testset "AdvancedHMC mid-chain failures do not return or cache partial fits" begin
    data = FacetData((; person = [1, 1, 1, 1, 2, 2, 2, 2],
        item = [1, 2, 3, 4, 1, 2, 3, 4], rater = [1, 2, 1, 2, 2, 1, 2, 1],
        score = [0, 1, 2, 0, 2, 1, 0, 2]);
        person = :person, item = :item, rater = :rater, score = :score)
    specs = (mfrm_spec(data),
        mfrm_spec(data; family = :gmfrm, thresholds = :partial_credit, discrimination = :rater),
        mfrm_spec(data; family = :mgmfrm, thresholds = :partial_credit, dimensions = 2,
            q_matrix = Bool[1 0; 1 0; 0 1; 0 1]))
    controls = (; backend = :advancedhmc, ndraws = 2, warmup = 2,
        max_depth = 2, step_size = 0.03, init_jitter = 0.0)
    for spec in specs
        println(stderr, "Checking mid-chain failures and cache preservation: ", spec.family)
        flush(stderr)
        fit_model = spec.family === :mfrm ? fit : B.Experimental.fit
        cache_model = spec.family === :mfrm ? cached_fit : B.Experimental.cached_fit
        counter = FailingRNG(MersenneTwister(31), typemax(Int), ErrorException("counter exhausted"), 0)
        complete = fit_model(spec; rng = counter, chains = 1, controls...)
        nparams = size(complete.draws, 2)
        used = typemax(Int) - counter.normals_left
        # The installed AdvancedHMC draws one momentum at initialization and per transition.
        # Verify that schedule before locating faults; it is not a public sampler API.
        @test used == nparams * (1 + controls.warmup + controls.ndraws)
        @test size(complete.draws, 1) == controls.ndraws
        @test only(sampler_diagnostics(complete; phase = :warmup)).observed_iterations == controls.warmup
        for completed_second_chain in (1, controls.warmup + 1), cause in (
                ErrorException("injected mid-chain failure"), InterruptException(),
                OutOfMemoryError(), StackOverflowError())
            # First chain complete; fail after one warmup or one retained transition in chain 2.
            budget = used + nparams * (1 + completed_second_chain)
            rng = FailingRNG(MersenneTwister(31), budget, cause, 0)
            failure = capture(() -> fit_model(spec; rng, chains = 3, controls...))
            @test rng.failures == 1 && rng.normals_left == 0
            if cause isa ErrorException
                @test failure isa B._SamplerError
                @test (failure.backend, failure.chain, failure.phase) == (:advancedhmc, 2, :sampling)
                @test failure.cause.ex === cause
                @test !isempty(failure.cause.processed_bt)
            else
                @test failure === cause
            end
        end
        mktempdir() do directory
            path = joinpath(directory, "fit.jls")
            for existing in (false, true)
                if existing
                    save_fit_cache(path, complete; cache_key = "original",
                        artifact = (; schema = "sampling_failure_check"))
                end
                before = existing ? read(path) : nothing
                for cause in (ErrorException("injected cached sampler failure"), InterruptException())
                    rng = FailingRNG(MersenneTwister(31),
                        used + nparams * (controls.warmup + 2), cause, 0)
                    failure = capture(() -> cache_model(spec; cache_path = path, refresh = existing,
                        rng, seed = 31, chains = 3, controls...))
                    @test rng.failures == 1
                    @test cause isa InterruptException ? failure === cause :
                        failure isa B._SamplerError && failure.chain == 2 && failure.cause.ex === cause
                    @test existing ? read(path) == before : !ispath(path)
                    @test readdir(directory) == (existing ? ["fit.jls"] : String[])
                end
                if existing
                    @test load_fit_cache(path; expected_cache_key = "original").draws == complete.draws
                end
            end
        end
    end
end
end # module FittingExceptionChecks
