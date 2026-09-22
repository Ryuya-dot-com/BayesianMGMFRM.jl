module PublicWarmupDiagnosticChecks
using Test, Random, Serialization, BayesianMGMFRM
const B = BayesianMGMFRM
include("test_groups.jl")

cells = [(p, i, r) for p in 1:2 for i in 1:4 for r in 1:3]
data = FacetData((; person = [p for (p, i, r) in cells],
    item = [i for (p, i, r) in cells], rater = [r for (p, i, r) in cells],
    score = [mod(p + i + r, 4) for (p, i, r) in cells]);
    person = :person, item = :item, rater = :rater, score = :score, category_levels = 0:3)
const specs = [mfrm_spec(data; thresholds = :partial_credit),
    mfrm_spec(data; family = :gmfrm, thresholds = :partial_credit, discrimination = :rater),
    mfrm_spec(data; family = :mgmfrm, dimensions = 2, thresholds = :partial_credit,
        q_matrix = Bool[1 0; 1 0; 0 1; 0 1])]
const controls = (; ndraws = 12, warmup = 10, chains = 2, seed = 9273,
    step_size = 0.03, max_depth = 4, init_jitter = 0.02)

function public_fit(spec, backend; kwargs...)
    mktempdir() do directory
        extra = backend === :cmdstan ? (; cmdstan_cache_dir = directory) : (;)
        fit_model = spec.family === :mfrm ? fit : B.Experimental.fit
        return fit_model(spec; backend, controls..., extra..., kwargs...)
    end
end

# The existing private option reproduces the pre-recording sampler path.
function unrecorded_fit(spec, backend)
    spec.family !== :mfrm && return public_fit(spec, backend; record_warmup = false)
    design, prior = getdesign(spec), MFRMPrior()
    rng, rng_control = B._fit_rng(Random.default_rng(), controls.seed)
    backend === :julia && return B._fit_random_walk(design, prior, controls.ndraws,
        controls.warmup, controls.chains, controls.step_size, initial_params(design),
        rng, rng_control; record_warmup = false)
    runner = backend === :advancedhmc ? B._fit_advancedhmc :
        backend === :turing ? B._fit_turing : B._fit_cmdstan
    return mktempdir() do directory
        extra = backend === :cmdstan ? (; cmdstan_path = nothing, cmdstan_cache_dir = directory) : (;)
        runner(design, prior, controls.ndraws, controls.warmup, controls.chains,
            controls.step_size, initial_params(design), rng, rng_control;
            target_accept = 0.8, max_depth = controls.max_depth, max_energy_error = 1000.0,
            metric = :diagonal, ad_backend = :ForwardDiff, init_jitter = controls.init_jitter,
            progress = false, record_warmup = false, extra...)
    end
end

replace_controls(f, controls) = typeof(f)((name === :sampler_controls ? controls :
    getfield(f, name) for name in fieldnames(typeof(f)))...)

function check_backend(backend)
    @testset "$backend public warmup diagnostics and cache compatibility" begin
        for spec in (backend in (:julia, :turing) ? specs[1:1] : specs)
            recorded = public_fit(spec, backend)
            old = unrecorded_fit(spec, backend)
            rows = sampler_diagnostics(recorded; phase = :warmup)
            @test length(rows) == controls.chains
            @test all(r -> r.phase === :warmup && r.backend === backend &&
                r.coverage === :recorded && r.expected_iterations == controls.warmup &&
                r.observed_iterations == controls.warmup, rows)
            @test getproperty.(rows, :chain) == [1, 2]
            @test all(r -> backend === :julia ?
                0 <= r.n_nonfinite_proposals <= controls.warmup &&
                all(ismissing, (r.n_divergences, r.n_max_treedepth, r.n_nonfinite_logdensity)) :
                all(n -> 0 <= n <= controls.warmup,
                    (r.n_divergences, r.n_max_treedepth, r.n_nonfinite_logdensity)), rows)
            for name in (:draws, :log_posterior, :sampler_stats, :chain_ids, :iterations,
                    :chain_acceptance_rate, :step_size)
                @test isequal(getproperty(recorded, name), getproperty(old, name))
            end
            @test isequal(diagnostics(recorded), diagnostics(old))
            @test isequal(sampler_diagnostics(recorded), sampler_diagnostics(recorded; phase = :retained))
            @test_throws ArgumentError sampler_diagnostics(recorded; phase = :all)
            @test all(r -> r.coverage === :not_recorded && ismissing(r.observed_iterations) &&
                ismissing(r.n_divergences), sampler_diagnostics(old; phase = :warmup))
            @test !hasproperty(old.sampler_controls, :warmup_diagnostics)
            @test all(r -> !r.is_adapt, recorded.sampler_stats)

            mktempdir() do directory
                for (label, f) in (("recorded", recorded), ("legacy", old))
                    path = joinpath(directory, label * ".jls")
                    record = save_fit_cache(path, f)
                    bytes = read(path)
                    loaded = load_fit_cache(path)
                    @test isequal(loaded.draws, f.draws)
                    @test isequal(diagnostics(loaded), diagnostics(f))
                    @test isequal(sampler_diagnostics(loaded; phase = :warmup),
                        sampler_diagnostics(f; phase = :warmup))
                    @test read(path) == bytes
                    @test record.schema == "bayesianmgmfrm.fit_cache.v1"
                    if label == "recorded"
                        @test isequal(record.artifact.reproducibility.sampler_controls.warmup_diagnostics, rows)
                        if backend in (:julia, :turing)
                            report = fit_report(f; require_complete = true, include_artifact = false,
                                include_posterior_predictive = false, include_category_functioning = false,
                                include_rater_homogeneity = false, include_calibration = false,
                                include_waic = false, include_loo = false)
                            @test isequal(report.warmup.rows, rows)
                            bundle = joinpath(directory, "report")
                            save_fit_report_bundle(bundle, fit_report_public(report))
                            @test load_fit_report_bundle(bundle)["warmup"]["rows"] == B._json_export_value(rows)
                            @test occursin("recorded", read(joinpath(bundle, "fit_report.md"), String))
                        end
                        badcount = backend === :julia ? (; n_nonfinite_proposals = controls.warmup + 1) :
                            (; n_divergences = controls.warmup + 1)
                        for badrows in (nothing, rows[1:1],
                                [merge(rows[1], (; chain = 2)), rows[2]],
                                [merge(rows[1], (; observed_iterations = controls.warmup - 1)), rows[2]],
                                [merge(rows[1], badcount), rows[2]],
                                [merge(rows[1], (; coverage = :not_recorded)), rows[2]])
                            bad = replace_controls(f, merge(f.sampler_controls, (; warmup_diagnostics = badrows)))
                            @test_throws ArgumentError sampler_diagnostics(bad; phase = :warmup)
                            @test_throws ArgumentError save_fit_cache(path, bad; overwrite = true)
                            @test read(path) == bytes
                            malformed = joinpath(directory, "malformed.jls")
                            serialize(malformed, merge(record, (; fit = bad)))
                            @test_throws ArgumentError load_fit_cache(malformed; verify_hash = false)
                        end
                    end
                end
            end
            zero = public_fit(spec, backend; warmup = 0)
            @test all(r -> r.coverage === :not_run && r.observed_iterations == 0 &&
                (backend === :julia ? r.n_nonfinite_proposals == 0 &&
                    all(ismissing, (r.n_divergences, r.n_max_treedepth, r.n_nonfinite_logdensity)) :
                    r.n_divergences == r.n_max_treedepth == r.n_nonfinite_logdensity == 0),
                sampler_diagnostics(zero; phase = :warmup))
        end
    end
end

check_backend(:julia)
check_backend(:advancedhmc)
check_backend(:turing)
test_flag("BAYESIANMGMFRM_CMDSTAN_TESTS") && check_backend(:cmdstan)

@testset "Turing adaptation ends before retained transitions" begin
    spec = first(specs)
    design = getdesign(spec)
    nparams = length(design.parameter_names)
    target = MFRMLogDensity(design)
    for warmup in (0, 1, 8)
        request = (; backend = :turing, warmup, ndraws = 6, chains = 1,
            step_size = 0.03, max_depth = 3, seed = 23)
        fitted = fit(spec; request...)
        longer = fit(spec; request..., ndraws = 10)
        # Asking for more posterior draws must not change adaptation or the prefix.
        @test fitted.draws == longer.draws[1:6, :]
        @test fitted.log_posterior == longer.log_posterior[1:6]
        @test isequal(fitted.sampler_stats, longer.sampler_stats[1:6])
        @test fitted.sampler_controls.nadapts == warmup
        @test fitted.sampler_controls.discard_initial == warmup + 1
        cache_request = B._fit_cache_request(design; request...)
        legacy_controls = merge(Base.structdiff(cache_request.controls, (; nadapts = nothing)),
            (; discard_initial = warmup == 0 ? 1 : warmup))
        @test fit_cache_key(spec; request...) !=
            B._cache_hash(merge(cache_request, (; controls = legacy_controls)))

        # Independent Turing call keeps the initial state and every transition;
        # state.i is the actual transition index, not a post-discard row number.
        states = NamedTuple[]
        callback = (rng, model, sampler, sample, state, iteration; kwargs...) ->
            push!(states, (; transition = state.i, nadapts = kwargs[:nadapts]))
        reference = B.Turing.sample(MersenneTwister(23),
            B._turing_mfrm_logdensity_model(target, nparams),
            B.Turing.NUTS(warmup, 0.8, 3, 1000.0, 0.03, B.AdvancedHMC.DiagEuclideanMetric;
                adtype = B.Turing.AutoForwardDiff()), warmup + 7;
            discard_initial = 0, progress = false, verbose = false, chain_type = Any,
            initial_params = B.Turing.InitFromParams((params = initial_params(design),)), callback)
        @test getproperty.(states, :transition) == collect(0:(warmup + 6))
        @test all(row -> row.nadapts == warmup, states)
        summary = only(sampler_diagnostics(fitted; phase = :warmup))
        warming = [t.stats for t in reference[2:(warmup + 1)]]
        @test summary.observed_iterations == warmup
        @test summary.coverage === (warmup == 0 ? :not_run : :recorded)
        @test summary.n_divergences == count(s -> s.numerical_error, warming)
        @test summary.n_max_treedepth == count(s -> s.tree_depth >= 3, warming)
        @test summary.n_nonfinite_logdensity == count(s -> !isfinite(s.log_density), warming)
        retained = reference[(warmup + 2):end]
        @test all(row -> row.transition > row.nadapts, states[(warmup + 2):end])
        @test fitted.draws == reduce(vcat, permutedims(B._turing_params(t, nparams)) for t in retained)
        @test fitted.log_posterior == [t.stats.log_density for t in retained]
        @test all(row -> !row.is_adapt, fitted.sampler_stats)
        @test length(unique(getproperty.(fitted.sampler_stats, :step_size))) == 1
        warmup == 0 && @test all(row -> row.step_size == 0.03, fitted.sampler_stats)
        @test fitted.chain_ids == ones(Int, 6) && fitted.iterations == collect(1:6)
        @test all(i -> fitted.log_posterior[i] ≈ logposterior(design, fitted.draws[i, :]), 1:6)

        mktempdir() do directory
            path = joinpath(directory, "fit.jls")
            key = fit_cache_key(spec; request...)
            save_fit_cache(path, fitted; cache_key = key)
            loaded = load_fit_cache(path; expected_cache_key = key)
            @test loaded.draws == fitted.draws
            @test loaded.sampler_controls.nadapts == warmup
            @test loaded.sampler_controls.discard_initial == warmup + 1
            @test isequal(diagnostics(loaded), diagnostics(fitted))
            @test isequal(sampler_diagnostics(loaded; phase = :warmup),
                sampler_diagnostics(fitted; phase = :warmup))
        end
    end
end

@testset "$backend recording preserves the RNG stream across chains" for backend in (:julia, :turing)
    design = getdesign(first(specs))
    rngs = [MersenneTwister(991), MersenneTwister(991)]
    fits = map(zip((true, false), rngs)) do (record_warmup, rng)
        _, rng_control = B._fit_rng(rng, nothing)
        backend === :julia && return B._fit_random_walk(design, MFRMPrior(), 4, 3, 2,
            0.03, initial_params(design), rng, rng_control; record_warmup)
        B._fit_turing(design, MFRMPrior(), 4, 3, 2, 0.03,
            initial_params(design), rng, rng_control; record_warmup,
            target_accept = 0.8, max_depth = 3, max_energy_error = 1000.0,
            metric = :diagonal, ad_backend = :ForwardDiff, init_jitter = 0.02, progress = false)
    end
    for field in (:draws, :log_posterior, :sampler_stats, :chain_ids, :iterations,
            :acceptance_rate, :chain_acceptance_rate, :step_size)
        @test isequal(getproperty(fits[1], field), getproperty(fits[2], field))
    end
    @test isequal(diagnostics(fits[1]), diagnostics(fits[2]))
    @test rand(copy(rngs[1]), UInt64, 16) == rand(copy(rngs[2]), UInt64, 16)
end

mutable struct ProposalRNG <: AbstractRNG
    normals::Vector{Float64}
    index::Int
end
Random.randn(rng::ProposalRNG) = rng.normals[rng.index += 1]
Random.rand(::ProposalRNG) = 0.5

@testset "random-walk warmup proposals stay separate from retained events" begin
    design = getdesign(first(specs))
    # Chain 1: two invalid warmup proposals, none retained. Chain 2: the reverse.
    invalid = Bool[1, 0, 1, 0, 0, 0, 0, 0, 0, 1, 1, 0]
    rng = ProposalRNG(repeat(ifelse.(invalid, 2.0, 0.0);
        inner = length(design.parameter_names)), 0)
    f = B._fit_random_walk(design, MFRMPrior(), 3, 3, 2, floatmax(Float64),
        initial_params(design), rng, (;); record_warmup = true)
    rows = sampler_diagnostics(f; phase = :warmup)
    @test getproperty.(rows, :n_nonfinite_proposals) == [2, 0]
    @test getproperty.(sampler_diagnostics(f), :n_nonfinite_proposals) == [0, 2]
    @test all(iszero, f.draws) && all(isfinite, f.log_posterior)
    @test all(r -> all(ismissing, (r.n_divergences, r.n_max_treedepth,
        r.n_nonfinite_logdensity)), rows)
    @test rng.index == length(rng.normals)
    for replacement in ((; n_divergences = 0), (; n_max_treedepth = 0),
            (; n_nonfinite_logdensity = 0), (; n_nonfinite_proposals = -1),
            (; n_nonfinite_proposals = missing), (; n_nonfinite_proposals = 1.0))
        badrows = [merge(first(rows), replacement), last(rows)]
        bad = replace_controls(f, merge(f.sampler_controls, (; warmup_diagnostics = badrows)))
        @test_throws ArgumentError sampler_diagnostics(bad; phase = :warmup)
    end
    @test all(r -> ismissing(r.n_nonfinite_proposals),
        sampler_diagnostics(replace_controls(f, (;)); phase = :warmup))
end

@testset "unavailable warmup is distinct from zero events" begin
    for backend in (:julia, :turing)
        f = unrecorded_fit(first(specs), backend)
        @test all(r -> r.coverage === :not_recorded && ismissing(r.n_divergences) &&
            ismissing(r.n_max_treedepth) && ismissing(r.n_nonfinite_logdensity),
            sampler_diagnostics(f; phase = :warmup))
        legacy_zero = MFRMFit(f.design, f.prior, f.draws, f.log_posterior,
            f.acceptance_rate, f.chain_ids, f.iterations, f.chain_acceptance_rate,
            f.backend, f.sampler, 0, f.step_size)
        @test all(r -> backend === :turing ?
            r.coverage === :not_recorded && ismissing(r.n_divergences) :
            r.coverage === :not_run && r.n_nonfinite_proposals == 0 && ismissing(r.n_divergences),
            sampler_diagnostics(legacy_zero; phase = :warmup))
    end
end
end
