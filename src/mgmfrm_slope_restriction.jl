# A restriction of the normalized target, with fixed blocks absent from the sampler.
struct _SlopeRestrictedSpec
    base_spec::FacetSpec
    item_slopes::Symbol
    function _SlopeRestrictedSpec(spec::FacetSpec; item_slopes::Symbol,
            rater_consistency::Symbol)
        item_slopes in (:fixed_one, :estimated_positive) || throw(ArgumentError(
            "item_slopes must be :fixed_one or :estimated_positive"))
        rater_consistency === :fixed_one || throw(ArgumentError(
            "slope_restriction currently requires rater_consistency=:fixed_one"))
        spec.family === :mgmfrm && spec.dimensions == 1 &&
            spec.thresholds === :partial_credit || throw(ArgumentError(
            "slope_restriction requires one-dimensional, item-step MGMFRM"))
        _check_guarded_mgmfrm_spec(spec)
        new(deepcopy(spec), item_slopes)
    end
end

# The old prior type and record remain unchanged; the profile is an opt-in policy.
struct _MGMFRMMeanProfilePrior
    base::_NormalizedMGMFRMPrior
    profile::NamedTuple
    function _MGMFRMMeanProfilePrior(model::_SlopeRestrictedSpec,
            base::_NormalizedMGMFRMPrior; item_means::AbstractDict,
            step_means::AbstractDict, category_levels, units::Symbol)
        model.item_slopes === :fixed_one && base.prior_model === :exchangeable ||
            throw(ArgumentError("MeanProfilePrior requires fixed-one item slopes and an exchangeable base prior"))
        units in (:raw, :unit_logit) || throw(ArgumentError("units must be :raw or :unit_logit"))
        data = model.base_spec.data
        isequal(collect(category_levels), data.category_levels) || throw(ArgumentError(
            "category_levels must match the model's complete declared category order"))
        items = data.item_levels
        Set(keys(item_means)) == Set(items) && Set(keys(step_means)) == Set(items) ||
            throw(ArgumentError("item_means and step_means must name every item ID exactly once"))
        number(x) = x isa Real && !(x isa Bool) && isfinite(x) && isfinite(Float64(x)) ?
            Float64(x) : throw(ArgumentError("profile means must be finite real numbers, not Bool"))
        divisor = units === :unit_logit ? 1.7 : 1.0
        locations = [number(item_means[i])/divisor for i in items]
        H = length(data.category_levels)-1
        steps = map(items) do i
            v = step_means[i]
            v isa AbstractVector && length(v) == H || throw(ArgumentError(
                "each item needs K-1 step means, excluding the structural baseline"))
            a = number.(v)./divisor
            abs(sum(a)) <= 64eps(Float64)*max(1.0, maximum(abs, a)) || throw(ArgumentError(
                "step means must sum to zero; overall location belongs in item_means"))
            # Canonical last reconstruction keeps density, initialization and prediction identical.
            a[end] = -sum(a[1:end-1])
            all(isfinite, a) || throw(ArgumentError("step mean reconstruction must remain finite"))
            a
        end
        new(base, (; units=:raw, item_levels=deepcopy(items),
            category_levels=deepcopy(data.category_levels), item_means=locations, step_means=steps))
    end
end

function _mean_profile_prior(model, base, profile)
    Set(keys(profile)) == Set((:units, :item_levels, :category_levels, :item_means, :step_means)) ||
        throw(ArgumentError("unrecognized mean-profile fields"))
    isequal(profile.item_levels, model.base_spec.data.item_levels) ||
        throw(ArgumentError("mean-profile item IDs/order do not match the model"))
    length(profile.item_means) == length(profile.step_means) == length(profile.item_levels) ||
        throw(ArgumentError("mean-profile owner/mean lengths differ"))
    return _MGMFRMMeanProfilePrior(model, base;
        item_means=Dict(zip(profile.item_levels, profile.item_means)),
        step_means=Dict(zip(profile.item_levels, profile.step_means)),
        category_levels=profile.category_levels, units=profile.units)
end
const _SlopePrior = Union{_NormalizedMGMFRMPrior,_MGMFRMMeanProfilePrior}

struct _MGMFRMSlopeLogDensity
    full::_MGMFRMNormalizedPriorLogDensity
    base::_MGMFRMGuardedLocalFitLogDensity
    blueprint::NamedTuple
    active::Vector{Int}
    item_slopes::Symbol
    prior_model::Symbol
    profile::Union{Nothing,NamedTuple}
    mean_shift::Vector{Float64}
end

function _normalized_mgmfrm_target(spec::_SlopeRestrictedSpec, prior::_NormalizedMGMFRMPrior)
    prior.prior_model === :exchangeable || throw(ArgumentError(
        "slope_restriction requires NormalizedMGMFRMPrior(prior_model=:exchangeable, ...)"))
    checked = _SlopeRestrictedSpec(spec.base_spec;
        item_slopes=spec.item_slopes, rater_consistency=:fixed_one)
    full = _normalized_mgmfrm_target(checked.base_spec, prior)
    bp = full.base.blueprint
    blocks = copy(bp.blocks); active = Int[]
    for block in (:person, :rater_free, :item, :log_item_dimension_discrimination,
            :log_rater_consistency_free, :item_steps)
        start = length(active) + 1
        fixed = block === :log_rater_consistency_free ||
            (block === :log_item_dimension_discrimination && checked.item_slopes === :fixed_one)
        fixed || append!(active, bp.blocks[block])
        blocks[block] = start:length(active)
    end
    blueprint = merge(bp, (; blocks, n_parameters=length(active),
        parameter_names=bp.parameter_names[active]))
    return _MGMFRMSlopeLogDensity(full, full.base, blueprint, active,
        checked.item_slopes, :exchangeable, nothing, zeros(length(active)))
end

function _normalized_mgmfrm_target(model::_SlopeRestrictedSpec, prior::_MGMFRMMeanProfilePrior)
    checked = _mean_profile_prior(model, prior.base, prior.profile)
    target = _normalized_mgmfrm_target(model, checked.base)
    shift = zeros(length(target.active))
    shift[target.blueprint.blocks[:item]] = checked.profile.item_means
    shift[target.blueprint.blocks[:item_steps]] = reduce(vcat,
        [v[1:end-1] for v in checked.profile.step_means]; init=Float64[])
    return _MGMFRMSlopeLogDensity(target.full, target.base, target.blueprint,
        target.active, target.item_slopes, target.prior_model, checked.profile, shift)
end
_normalized_mgmfrm_target(model, prior::_MGMFRMMeanProfilePrior) = throw(ArgumentError(
    "MeanProfilePrior requires an independent D1 fixed-one slope_restriction model"))

function _slope_full_raw(target::_MGMFRMSlopeLogDensity, raw::AbstractVector)
    _check_source_fixture_raw_vector(target, raw)
    x = zeros(eltype(raw), LogDensityProblems.dimension(target.full))
    x[target.active] = raw
    return x
end
function _check_source_fixture_raw_vector(t::_MGMFRMSlopeLogDensity, raw::AbstractVector)
    length(raw) == length(t.active) && all(isfinite, raw) || throw(ArgumentError(
        "slope-restricted raw coordinates must be finite and match the free-parameter layout"))
    return nothing
end
LogDensityProblems.dimension(t::_MGMFRMSlopeLogDensity) = length(t.active)
LogDensityProblems.capabilities(::Type{_MGMFRMSlopeLogDensity}) = LogDensityProblems.LogDensityOrder{0}()
initial_params(t::_MGMFRMSlopeLogDensity) = copy(t.mean_shift)
function logprior(t::_MGMFRMSlopeLogDensity, raw::AbstractVector)
    # Remove the density factors of fixed, independent blocks. Zero SDs are not priors.
    R = length(t.base.design.spec.data.rater_levels)
    s = t.base.prior
    constant = (R-1)*(-log(s.log_consistency_sd)-log(2pi)/2)+log(R)/2
    if t.item_slopes === :fixed_one
        constant += length(t.base.blueprint.blocks[:log_item_dimension_discrimination]) *
            (-log(s.log_discrimination_sd)-log(2pi)/2)
    end
    residual = t.profile === nothing ? raw : raw .- t.mean_shift
    return logprior(t.full, _slope_full_raw(t, residual))-constant
end
LogDensityProblems.logdensity(t::_MGMFRMSlopeLogDensity, raw) =
    _source_fixture_loglikelihood(t.base, _slope_full_raw(t, raw))+logprior(t, raw)

function _mgmfrm_normalized_prior_record(t::_MGMFRMSlopeLogDensity)
    original = merge(_mgmfrm_normalized_prior_record(t.full), (;
        schema=Symbol("bayesianmgmfrm.normalized_slope_restricted_prior.v1"),
        item_slopes=t.item_slopes, rater_consistency=:fixed_one))
    t.profile === nothing && return original
    return merge(original, (; schema=Symbol("bayesianmgmfrm.normalized_mean_profile_prior.v1"),
        mean_profile=deepcopy(t.profile)))
end
_mgmfrm_normalized_prior_identity(t::_MGMFRMSlopeLogDensity) = _cache_hash((;
    design=design_identity(t.base.design).value, prior=_mgmfrm_normalized_prior_record(t)))

function _restore_slope_target(spec, record; expected_identity)
    profiled = record.schema === Symbol("bayesianmgmfrm.normalized_mean_profile_prior.v1")
    fields = (:schema, :prior_model, :scale_convention, :parameter_measure,
        :source_rater, :scales, :item_slopes, :rater_consistency)
    Set(keys(record)) == Set(profiled ? (fields..., :mean_profile) : fields) ||
        throw(ArgumentError("unrecognized slope-restricted prior fields"))
    prior = _NormalizedMGMFRMPrior(; prior_model=record.prior_model,
        source_rater=record.source_rater, record.scales...)
    model = _SlopeRestrictedSpec(spec; record.item_slopes, record.rater_consistency)
    profiled && (prior = _mean_profile_prior(model, prior, record.mean_profile))
    target = _normalized_mgmfrm_target(model, prior)
    isequal(record, _mgmfrm_normalized_prior_record(target)) &&
        _mgmfrm_normalized_prior_identity(target) == expected_identity ||
        throw(ArgumentError("slope-restricted prior contract or identity mismatch"))
    return target
end

_normalized_mgmfrm_blueprint(t::_MGMFRMSlopeLogDensity) = t.blueprint
_normalized_mgmfrm_model(t::_MGMFRMSlopeLogDensity) = Symbol("mgmfrm_slopes_",t.item_slopes)
function _mgmfrm_normalized_prior_metadata(t::_MGMFRMSlopeLogDensity)
    m = _mgmfrm_normalized_prior_metadata(t.full)
    loading = t.item_slopes === :fixed_one ? merge(m.blocks.log_loading,
        (; distribution=:point_mass, mean=0.0, sd=0.0, scale_active=false)) : m.blocks.log_loading
    consistency = merge(m.blocks.log_consistency, (; distribution=:point_mass,
        free_dimension=0, marginal_sd=0.0, contrast_sd=0.0, scale_active=false))
    blocks = merge(m.blocks, (; log_loading=loading, log_consistency=consistency))
    label = "Normalized exchangeable prior; item slopes $(t.item_slopes), rater consistency fixed at one; centered-block scales are kernel SDs"
    if t.profile !== nothing
        blocks = merge(blocks, (;
            item=merge(blocks.item, (; mean=copy(t.profile.item_means))),
            item_steps=merge(blocks.item_steps, (; mean=deepcopy(t.profile.step_means),
                residual_exchangeable=true, full_prior_exchangeable=all(v->all(iszero,v), t.profile.step_means),
                hard_ordered=false, units=:raw))))
        label = "Fixed mean-profile prior; exchangeable zero-sum residuals and raters; full step law follows the declared means; raw means and kernel SDs; item slopes and rater consistency fixed at one; no hard step ordering"
    end
    return merge(m, (; target_identity=_mgmfrm_normalized_prior_identity(t),
        prior=_mgmfrm_normalized_prior_record(t), loading_policy=t.item_slopes,
        rater_consistency=:fixed_one,
        prior_label=label, blocks))
end

function _generalized_candidate_direct_draw_values(t::_MGMFRMSlopeLogDensity, draws::AbstractMatrix{<:Real})
    full = zeros(size(draws,1), LogDensityProblems.dimension(t.full))
    full[:,t.active] = draws
    _generalized_candidate_direct_draw_values(t.base, full)
end
_generalized_candidate_direct_draw_constraint_rows(t::_MGMFRMSlopeLogDensity, direct::AbstractMatrix{<:Real}) =
    _generalized_candidate_direct_draw_constraint_rows(t.base, direct)
_normalized_mgmfrm_tables(t::_MGMFRMSlopeLogDensity, run) =
    _generalized_candidate_diagnostic_tables(t, run, t.blueprint)

function _normalized_mgmfrm_fit(spec::_SlopeRestrictedSpec, prior::_SlopePrior;
        backend::Symbol=:advancedhmc, init=nothing, sampling_coordinates::Symbol=:raw,
        record_warmup::Bool=true, kwargs...)
    backend === :advancedhmc && sampling_coordinates === :raw || throw(ArgumentError(
        "slope_restriction currently supports Julia :advancedhmc with :raw coordinates only"))
    target = _normalized_mgmfrm_target(spec, prior)
    init === nothing || init isa AbstractVector{<:Real} ||
        throw(ArgumentError("init must contain only free raw coordinates, in fit-layout order"))
    initial = init === nothing ? initial_params(target) : Float64.(collect(init))
    run = _run_generalized_candidate_advancedhmc(target, initial; record_warmup, kwargs...)
    record = (; schema=record_warmup ? "bayesianmgmfrm.normalized_fixed_q_samples.v2" :
        "bayesianmgmfrm.normalized_fixed_q_samples.v1", spec=deepcopy(target.base.design.spec),
        prior=_mgmfrm_normalized_prior_record(target),
        target_identity=_mgmfrm_normalized_prior_identity(target), run)
    record = merge(record, (; content_hash=_mgmfrm_normalized_sample_hash(record)))
    return _NormalizedMGMFRMFit(record; expected_identity=record.target_identity)
end

function _mgmfrm_normalized_prior_predictive_check(t::_MGMFRMSlopeLogDensity;
        ndraws::Int=1000, rng::AbstractRNG=Random.default_rng(),
        min_category_probability::Real=0.01, prior_warning_probability::Real=0.95,
        wide_facet_range_fraction::Real=0.8)
    _check_prior_implication_controls(; min_category_probability,
        prior_warning_probability, wide_facet_range_fraction)
    raw = _guarded_generalized_prior_draws(t.full, ndraws, rng)
    inactive = setdiff(1:size(raw,2), t.active); raw[:,inactive] .= 0
    t.profile === nothing || (raw[:,t.active] .+= transpose(t.mean_shift))
    m = _mgmfrm_normalized_prior_metadata(t)
    full = _generalized_prior_bundle_from_draws(t.base, raw; prior_record=m.prior)
    bundle = merge(full, (; raw_draws=raw[:,t.active], raw_parameter_names=t.blueprint.parameter_names))
    check = _generalized_prior_check_from_bundle(bundle; prior_record=m.prior, rng,
        min_category_probability, prior_warning_probability, wide_facet_range_fraction)
    merge(check, (; schema="bayesianmgmfrm.normalized_mgmfrm_prior_predictive_check.v1",
        target_identity=m.target_identity, prior_metadata=m, prior_label=m.prior_label, public_fit=false))
end

function Base.show(io::IO, spec::_SlopeRestrictedSpec)
    print(io,"Slope-restricted MGMFRM (item slopes ",spec.item_slopes,
        "; rater consistency fixed at one; experimental)")
end

function model_family_contract(spec::_SlopeRestrictedSpec)
    checked = _SlopeRestrictedSpec(spec.base_spec; item_slopes=spec.item_slopes, rater_consistency=:fixed_one)
    original = model_family_contract(checked.base_spec)
    merge(original, (; branch=:mgmfrm_slope_restricted,
        dimensionality=merge(original.dimensionality, (; current_loading_policy=checked.item_slopes)),
        loading_policy=checked.item_slopes, rater_consistency=:fixed_one,
        step_owner=:item, likelihood_scale=1.7, scientific_acceptance=:not_established))
end
