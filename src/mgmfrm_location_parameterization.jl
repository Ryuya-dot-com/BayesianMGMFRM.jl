# Optional computational coordinates; existing defaults and stored raw coordinates stay intact.
function _check_mgmfrm_sampling_coordinates(spec::FacetSpec, coordinates::Symbol,
        backend::Symbol, experimental::Bool)
    coordinates in (:raw, :orthogonal_person_mean_item_offset) || throw(ArgumentError(
        "sampling_coordinates must be :raw or :orthogonal_person_mean_item_offset"))
    if coordinates !== :raw
        experimental && spec.family === :mgmfrm && backend === :advancedhmc ||
            throw(ArgumentError("orthogonal_person_mean_item_offset requires an independent fixed-Q MGMFRM with backend = :advancedhmc"))
    end
    return nothing
end

struct _MGMFRMLocationLogDensity
    base::_MGMFRMGuardedLocalFitLogDensity
    reflector::Vector{Float64}
end

function _MGMFRMLocationLogDensity(base::_MGMFRMGuardedLocalFitLogDensity)
    base = _mgmfrm_guarded_local_fit_logdensity(base.design; prior = base.prior)
    n = length(base.design.spec.data.person_levels)
    # Symmetric orthogonal H maps e1 to 1/sqrt(n); no dense n-by-n matrix.
    v = fill(-inv(sqrt(n)), n)
    v[1] += 1
    n > 1 ? (v ./= norm(v)) : fill!(v, 0)
    return _MGMFRMLocationLogDensity(base, v)
end

function _mgmfrm_location_transform(target::_MGMFRMLocationLogDensity,
        values::AbstractVector, to_raw::Bool)
    base = target.base
    _check_source_fixture_raw_vector(base, values)
    blocks, spec = base.blueprint.blocks, base.design.spec
    D, n = spec.dimensions, length(target.reflector)
    means = [to_raw ? values[blocks[:person][d]] / sqrt(n) :
        mean(view(values, blocks[:person][d:D:end])) for d in 1:D]
    out = values .+ 0.0 # Preserve automatic-differentiation scalars and accept integer input.
    for d in 1:D
        persons = view(out, blocks[:person][d:D:end])
        persons .-= (2dot(target.reflector, persons)) .* target.reflector
    end
    loading = first(blocks[:log_item_dimension_discrimination])
    for i in axes(spec.q_matrix, 1), d in 1:D
        spec.q_matrix[i, d] || continue
        offset = exp(values[loading]) * means[d]
        out[blocks[:item][i]] += to_raw ? offset : -offset
        loading += 1
    end
    all(isfinite, out) || throw(ArgumentError("nonfinite MGMFRM location transform"))
    return out
end

_mgmfrm_location_to_raw(target::_MGMFRMLocationLogDensity, values::AbstractVector) =
    _mgmfrm_location_transform(target, values, true)
_mgmfrm_location_from_raw(target::_MGMFRMLocationLogDensity, values::AbstractVector) =
    _mgmfrm_location_transform(target, values, false)

LogDensityProblems.dimension(target::_MGMFRMLocationLogDensity) =
    LogDensityProblems.dimension(target.base)
LogDensityProblems.capabilities(::Type{_MGMFRMLocationLogDensity}) =
    LogDensityProblems.LogDensityOrder{0}()
_check_source_fixture_raw_vector(target::_MGMFRMLocationLogDensity, values::AbstractVector) =
    _check_source_fixture_raw_vector(target.base, values)
initial_params(target::_MGMFRMLocationLogDensity) =
    _mgmfrm_location_from_raw(target, initial_params(target.base))

function LogDensityProblems.logdensity(target::_MGMFRMLocationLogDensity, values)
    # Orthogonal person rotation followed by a triangular item translation has
    # |det J| = 1, even though the translation depends on sampled loadings.
    # Evaluate the ORIGINAL joint prior at (theta, b), not independent priors on offsets.
    return LogDensityProblems.logdensity(target.base, _mgmfrm_location_to_raw(target, values))
end

function _fit_mgmfrm_location(spec::FacetSpec;
        prior = nothing, init = nothing, kwargs...)
    _check_guarded_mgmfrm_spec(spec)
    base = _mgmfrm_guarded_local_fit_logdensity(spec; prior = _guarded_mgmfrm_prior(prior))
    target = _MGMFRMLocationLogDensity(base)
    raw_initial = _guarded_mgmfrm_initial(base, init)
    run = _run_generalized_candidate_advancedhmc(target, raw_initial;
        _initial_transform = x -> _mgmfrm_location_from_raw(target, x),
        record_warmup = true, kwargs...)
    raw_draws = reduce(vcat, [permutedims(_mgmfrm_location_to_raw(target, row))
        for row in eachrow(run.draws)])
    canonical = merge(run, (; draws = raw_draws, initial = raw_initial,
        controls = merge(run.controls, (;
            sampling_coordinates = :orthogonal_person_mean_item_offset,
            stored_coordinates = :raw_unconstrained,
            initialization_coordinates = :raw_unconstrained,
            coordinate_logabsdet = 0.0))))
    surface = _mgmfrm_guarded_local_fit_diagnostic_surface(base, canonical;
        initial_source = init === nothing ? :default_zero_raw : :user_supplied_raw)
    return _mgmfrm_fit_from_sampler_diagnostics(base.design, base.prior, surface)
end
