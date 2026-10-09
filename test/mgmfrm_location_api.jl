# Also runs the mathematical/cache checks when invoked as a standalone test.
isdefined(@__MODULE__, :MGMFRMLocationParameterizationChecks) ||
    include("mgmfrm_location_parameterization.jl")

module MGMFRMLocationAPIChecks
using Test, Random, SHA, BayesianMGMFRM
using ..MGMFRMLocationParameterizationChecks: specification
const B = BayesianMGMFRM
const E = B.Experimental
const COORDINATES = :orthogonal_person_mean_item_offset
digest(path) = bytes2hex(sha256(read(path)))

@testset "MGMFRM sampling coordinates distinguish computation, not the model" begin
    spec = specification(3, Bool[1 0; 1 0; 0 1; 0 1])
    prior = E.GeneralizedPrior(person_sd = 1.3, item_sd = .7)
    base = B._mgmfrm_guarded_local_fit_logdensity(spec; prior = B._source_fixture_prior(prior))
    initial = .05randn(MersenneTwister(924), length(B.initial_params(base)))
    options = (; prior, init = initial, seed = 92342, chains = 2,
        ndraws = 16, warmup = 12, max_depth = 3, init_jitter = .1, step_size = .03)
    default_key = E.fit_cache_key(spec; options...)
    location_key = E.fit_cache_key(spec; sampling_coordinates = COORDINATES, options...)
    @test default_key == E.fit_cache_key(spec; sampling_coordinates = :raw, options...)
    @test default_key != location_key
    @test location_key == E.fit_cache_key(spec; sampling_coordinates = COORDINATES,
        progress = true, options...)
    @test location_key == fit_cache_key(spec; experimental = true,
        backend = :advancedhmc, sampling_coordinates = COORDINATES, options...)
    @test location_key != E.fit_cache_key(spec; sampling_coordinates = COORDINATES,
        options..., seed = 92343)
    @test location_key != E.fit_cache_key(spec; sampling_coordinates = COORDINATES,
        options..., prior = E.GeneralizedPrior(person_sd = 1.4, item_sd = .7))
    raw_request = B._fit_cache_request(base.design; experimental = true,
        backend = :advancedhmc, options...)
    location_request = B._fit_cache_request(base.design; experimental = true,
        backend = :advancedhmc, sampling_coordinates = COORDINATES, options...)
    @test !haskey(raw_request.controls, :sampling_coordinates)
    @test location_request.controls.sampling_coordinates === COORDINATES
    @test isequal(Base.structdiff(raw_request, (; controls = nothing)),
        Base.structdiff(location_request, (; controls = nothing)))
    @test isequal(raw_request.controls,
        Base.structdiff(location_request.controls, (; sampling_coordinates = nothing)))

    fitted = E.fit(spec; sampling_coordinates = COORDINATES, options...)
    @test fitted isa B.MGMFRMFit
    @test fitted.sampler_controls.sampling_coordinates === COORDINATES
    @test fitted.sampler_controls.stored_coordinates === :raw_unconstrained
    @test B._source_fixture_prior_values(fitted.prior) == B._source_fixture_prior_values(base.prior)
    @test fitted.diagnostic_surface.initialization_policy.initial_raw_hash == B._cache_hash(initial)
    @test B.design_identity(fitted.design).value == B.design_identity(base.design).value
    @test length(diagnostics(fitted; include_location = true).location_rows) == 14
    @test isequal(diagnostics(fitted).summary, diagnostics(fitted; include_location = true).summary)

    mktempdir() do directory
        raw_path, location_path = joinpath.(directory, ("raw.jls", "location.jls"))
        raw = E.cached_fit(spec; cache_path = raw_path, return_record = true, options...)
        location = E.cached_fit(spec; cache_path = location_path, return_record = true,
            sampling_coordinates = COORDINATES, options...)
        @test raw.cache_key == default_key
        @test location.cache_key == location_key
        @test isequal(location.fit.draws, fitted.draws)
        @test isequal(location.fit.sampler_stats, fitted.sampler_stats)
        @test !isequal(raw.fit.draws, fitted.draws)
        raw_hash, location_hash = digest(raw_path), digest(location_path)
        hit = E.cached_fit(spec; cache_path = location_path, return_record = true,
            sampling_coordinates = COORDINATES, options...)
        @test hit.created_at == location.created_at
        @test isequal(hit.fit.draws, fitted.draws)
        @test isequal(hit.fit.sampler_controls, fitted.sampler_controls)
        @test digest(location_path) == location_hash
        raw_hit = E.cached_fit(spec; cache_path = raw_path, return_record = true,
            sampling_coordinates = :raw, options...)
        @test raw_hit.created_at == raw.created_at
        @test isequal(raw_hit.fit.draws, raw.fit.draws)
        @test digest(raw_path) == raw_hash
        @test_throws ArgumentError E.cached_fit(spec; cache_path = raw_path,
            sampling_coordinates = COORDINATES, options...)
        @test_throws ArgumentError E.cached_fit(spec; cache_path = location_path, options...)
        @test_throws ArgumentError E.cached_fit(spec; cache_path = location_path,
            sampling_coordinates = :unknown, refresh = true, options...)
        @test_throws ArgumentError E.cached_fit(spec; cache_path = location_path,
            sampling_coordinates = COORDINATES, refresh = true, options..., ndraws = 0)
        @test digest(raw_path) == raw_hash
        @test digest(location_path) == location_hash
        restored = load_fit_cache(location_path; expected_cache_key = location_key)
        @test isequal(diagnostics(restored; include_location = true),
            diagnostics(fitted; include_location = true))
    end

    @test_throws ArgumentError E.fit(spec; sampling_coordinates = :unknown, options...)
    @test_throws ArgumentError E.fit_cache_key(spec; sampling_coordinates = :unknown, options...)
    @test_throws ArgumentError E.fit(spec; backend = :cmdstan,
        sampling_coordinates = COORDINATES, options...)
    @test_throws ArgumentError E.fit_cache_key(spec; backend = :cmdstan,
        sampling_coordinates = COORDINATES, options...)
    gmfrm = mfrm_spec(spec.data; family = :gmfrm, thresholds = :partial_credit, discrimination = :rater)
    @test_throws ArgumentError E.fit(gmfrm; sampling_coordinates = COORDINATES)
    @test_throws ArgumentError E.fit_cache_key(gmfrm; sampling_coordinates = COORDINATES, seed = 1)
    @test_throws ArgumentError E.fit(E.correlated(spec);
        sampling_coordinates = COORDINATES, prior)
    fixed = mfrm_spec(spec.data; family = :mfrm, dimensions = 2,
        thresholds = :partial_credit, q_matrix = spec.q_matrix)
    @test_throws ArgumentError E.fit(fixed; sampling_coordinates = COORDINATES)
    mfrm = mfrm_spec(spec.data; thresholds = :partial_credit)
    @test_throws ArgumentError fit_cache_key(mfrm; sampling_coordinates = COORDINATES, seed = 1)
end

end
