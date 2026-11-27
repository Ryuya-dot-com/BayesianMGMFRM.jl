# CR4: Multiplicative Scale-Identified Fixed-Q MGMFRM
#
# Resolves multiplicative scale non-identification between item loadings a_{id}
# and person abilities theta_{pd} in 1D and multidimensional fixed-Q MGMFRM via:
#   1. `:geometric_mean_one` (default, label-permutation-invariant):
#      orthonormal Helmert zero-sum structural log-loadings within each dimension's
#      pure-item set (prod_{i in I_d} tilde_a_{id} = 1, equal marginal prior SD
#      `log_loading_sd`), with estimated population ability SD `sigma_{theta_d}`.
#   2. `:anchor_item`:
#      explicit pure reference item `tilde_a_{i_0(d), d} = 1.0` per dimension,
#      independent Normal(0, log_loading_sd^2) on remaining active log-loadings,
#      with estimated population ability SD `sigma_{theta_d}`.
# Both modes expose structural `loading[i, dim=d]` (tilde_a_{id}), population
# `ability_sd[dim=d]` (sigma_{theta_d}), and unit-variance population
# `standardized_loading[i, dim=d]` (a^std_{id} = tilde_a_{id} * sigma_{theta_d}).

module ScaleIdentifiedMGMFRM

import ..BayesianMGMFRM as B
import LogDensityProblems as L
import SpecialFunctions
using Distributions: Normal, LogNormal, TDist, LocationScale, Truncated, Chisq, Beta, params
using LinearAlgebra
using Random
using SHA
using SparseArrays: SparseMatrixCSC, sparse, spzeros, dropzeros!
using Statistics

const PRIOR_SCHEMA = "bayesianmgmfrm.scale_identified_mgmfrm_prior.v1"
const TARGET_SCHEMA = "bayesianmgmfrm.scale_identified_mgmfrm_target.v1"
const FIT_SCHEMA = "bayesianmgmfrm.scale_identified_mgmfrm_fit.v1"
const REPORT_SCHEMA = "bayesianmgmfrm.scale_identified_mgmfrm_report.v1"
const PREDICTION_SCHEMA = "bayesianmgmfrm.scale_identified_mgmfrm_prediction.v1"
const PPC_SCHEMA = "bayesianmgmfrm.scale_identified_mgmfrm_ppc.v1"
const WEIGHTED_SCORE_SCHEMA = "bayesianmgmfrm.weighted_sufficient_score.v1"
const REPORT_SCHEMAS = (REPORT_SCHEMA, PREDICTION_SCHEMA, PPC_SCHEMA, WEIGHTED_SCORE_SCHEMA)

_fmt_label(x) = x isa AbstractString ? String(x) : string(x)

# Evaluate log(1 - tanh(x)^2) before tanh rounds to +/-1; do not clip correlations.
_logsech2(x) = 2 * (log(2) - abs(x) - log1p(exp(-2abs(x))))

function _pos_real(x, name::AbstractString)
    x isa Real && !(x isa Bool) && isfinite(x) ||
        throw(ArgumentError("$name must be a finite positive real number"))
    v = Float64(x)
    isfinite(v) && v > 0.0 ||
        throw(ArgumentError("$name must be positive after Float64 conversion"))
    return v
end

function _fin_real(x, name::AbstractString)
    x isa Real && !(x isa Bool) && isfinite(x) ||
        throw(ArgumentError("$name must be a finite real number"))
    v = Float64(x)
    isfinite(v) || throw(ArgumentError("$name overflowed Float64"))
    return v
end

function _parse_sim_ability_sd_prior(ability_sd_prior, ability_logsd_prior, ability_logsd_mean, ability_logsd_sd)
    if ability_sd_prior !== nothing
        (ability_logsd_prior === nothing && ability_logsd_mean === nothing && ability_logsd_sd === nothing) ||
            throw(ArgumentError("supply either ability_sd_prior or ability_logsd_prior/(ability_logsd_mean, ability_logsd_sd), not both"))
        if ability_sd_prior isa LogNormal
            p_mu, p_sd = params(ability_sd_prior)
            return (:lognormal, _fin_real(p_mu, "ability_sd_prior logmean"), _pos_real(p_sd, "ability_sd_prior logsd"), 1.0, Inf)
        elseif ability_sd_prior isa Truncated
            lo = Float64(ability_sd_prior.lower)
            hi = Float64(ability_sd_prior.upper)
            (lo == 0.0 && isinf(hi) && hi > 0.0) ||
                throw(ArgumentError("truncated ability_sd_prior must be supported on [0, Inf)"))
            u = ability_sd_prior.untruncated
            if u isa Normal
                Float64(u.μ) == 0.0 || throw(ArgumentError("HalfNormal ability_sd_prior must have location 0"))
                return (:half_normal, 0.0, 1.0, _pos_real(u.σ, "ability_sd_prior scale"), Inf)
            elseif u isa TDist
                return (:half_t, 0.0, 1.0, 1.0, _pos_real(u.ν, "ability_sd_prior df"))
            elseif u isa LocationScale && u.ρ isa TDist
                Float64(u.μ) == 0.0 || throw(ArgumentError("Half-t ability_sd_prior must have location 0"))
                return (:half_t, 0.0, 1.0, _pos_real(u.σ, "ability_sd_prior scale"), _pos_real(u.ρ.ν, "ability_sd_prior df"))
            end
        end
        throw(ArgumentError(
            "ability_sd_prior must be LogNormal(mu, sigma), truncated(Normal(0, s), 0, Inf), or truncated(LocationScale(0, s, TDist(df)), 0, Inf)"))
    end
    if ability_logsd_prior !== nothing && (ability_logsd_mean !== nothing || ability_logsd_sd !== nothing)
        throw(ArgumentError("supply either ability_logsd_prior or (ability_logsd_mean, ability_logsd_sd), not both"))
    end
    mu_sig, tau_sig = if ability_logsd_prior !== nothing
        p_mu, p_sd = params(ability_logsd_prior)
        (_fin_real(p_mu, "ability_logsd_prior mean"), _pos_real(p_sd, "ability_logsd_prior sd"))
    else
        (_fin_real(something(ability_logsd_mean, 0.0), "ability_logsd_mean"),
         _pos_real(something(ability_logsd_sd, 1.0), "ability_logsd_sd"))
    end
    isfinite(exp(mu_sig)) && exp(mu_sig) > 0.0 ||
        throw(ArgumentError("exp(ability_logsd_mean) must be finite and positive"))
    return (:lognormal, mu_sig, tau_sig, 1.0, Inf)
end

struct Prior
    scale_identification::Symbol
    location_identification::Symbol
    logit_scale::Float64
    rater_consistency::Symbol
    anchor_items::Any
    ability_logsd_mean::Float64
    ability_logsd_sd::Float64
    ability_mean_sd::Float64
    log_loading_sd::Float64
    item_sd::Float64
    rater_sd::Float64
    log_consistency_sd::Float64
    step_sd::Float64
    ability_sd_family::Symbol
    ability_sd_scale::Float64
    ability_sd_df::Float64
    latent_correlation::Symbol
    lkj_eta::Float64
    item_slopes::Symbol
    item_slope_scope::Symbol
    step_owner::Symbol
    family_tag::Symbol
    item_role::Symbol
    rater_slope_scope::Symbol
    aggregation::Symbol
    cross_loading_average::Bool
    softmin_kappa_mode::Symbol
    softmin_kappa::Float64
    softmin_log_kappa_mean::Float64
    softmin_log_kappa_sd::Float64

    function Prior(;
            scale_identification::Symbol = :geometric_mean_one,
            location_identification::Symbol = :zero_mean_population,
            logit_scale::Real = 1.7,
            rater_consistency::Symbol = :estimated_positive,
            anchor_items = nothing,
            ability_sd_prior = nothing,
            ability_logsd_prior::Union{Nothing, Normal, LogNormal} = nothing,
            ability_logsd_mean::Union{Nothing, Real} = nothing,
            ability_logsd_sd::Union{Nothing, Real} = nothing,
            ability_mean_sd::Real = 1.5,
            log_loading_sd::Union{Nothing, Real} = nothing,
            log_discrimination_sd::Union{Nothing, Real} = nothing,
            item_sd::Real = 1.0,
            rater_sd::Real = 1.0,
            log_consistency_sd::Real = 0.5,
            step_sd::Real = 1.0,
            latent_correlation::Union{Nothing, Symbol} = nothing,
            correlation::Union{Nothing, Symbol} = nothing,
            lkj_eta::Real = 2.0,
            item_slopes::Symbol = :estimated_positive,
            item_slope_scope::Symbol = :ability_only,
            step_owner::Symbol = :item,
            family_tag::Symbol = :mgmfrm,
            item_role::Symbol = :item,
            rater_slope_scope::Symbol = :entire_linear_predictor,
            aggregation::Symbol = :additive,
            cross_loading_average::Union{Nothing, Bool} = nothing,
            softmin_kappa = nothing,
            softmin_log_kappa_mean::Real = 0.0,
            softmin_log_kappa_sd::Real = 1.0)
        scale_identification in (:geometric_mean_one, :anchor_item) || throw(ArgumentError(
            "scale_identification must be :geometric_mean_one or :anchor_item; got $(repr(scale_identification))"))
        location_identification in (:zero_mean_population, :centered_items_free_mean) || throw(ArgumentError(
            "location_identification must be :zero_mean_population or :centered_items_free_mean; got $(repr(location_identification))"))
        s0 = _fin_real(logit_scale, "logit_scale")
        s0 in (1.7, 1.0) || throw(ArgumentError(
            "logit_scale must be 1.7 (Uto 2021 scale) or 1.0 (unit-logit GPCM scale); got $s0"))
        rater_consistency in (:estimated_positive, :fixed_one) || throw(ArgumentError(
            "rater_consistency must be :estimated_positive or :fixed_one; got $(repr(rater_consistency))"))
        item_slopes in (:estimated_positive, :fixed_one) || throw(ArgumentError(
            "item_slopes must be :estimated_positive or :fixed_one; got $(repr(item_slopes))"))
        item_slope_scope in (:ability_only, :entire_linear_predictor) || throw(ArgumentError(
            "item_slope_scope must be :ability_only or :entire_linear_predictor; got $(repr(item_slope_scope))"))
        rs_scope = rater_slope_scope === :linear_predictor ? :entire_linear_predictor : rater_slope_scope
        rs_scope in (:entire_linear_predictor, :ability_only) || throw(ArgumentError(
            "rater_slope_scope must be :entire_linear_predictor or :ability_only; got $(repr(rater_slope_scope))"))
        if item_slope_scope === :entire_linear_predictor && rs_scope === :ability_only && rater_consistency === :estimated_positive
            throw(ArgumentError("cannot combine item_slope_scope = :entire_linear_predictor with rater_slope_scope = :ability_only when rater_consistency is estimated"))
        end
        aggregation in (:additive, :softmin) || throw(ArgumentError(
            "aggregation must be :additive or :softmin; got $(repr(aggregation))"))
        cl_avg = something(cross_loading_average, aggregation === :softmin)
        if aggregation === :softmin && !cl_avg
            throw(ArgumentError("aggregation = :softmin requires cross_loading_average = true so balanced skill profiles remain invariant to dimension count"))
        end
        sk_lmean = _fin_real(softmin_log_kappa_mean, "softmin_log_kappa_mean")
        sk_lsd = _pos_real(softmin_log_kappa_sd, "softmin_log_kappa_sd")
        sk_mode, sk_val = if aggregation === :additive
            (softmin_kappa === nothing || softmin_kappa === :none) || throw(ArgumentError(
                "softmin_kappa applies only when aggregation = :softmin"))
            (:none, 1.0)
        else
            if softmin_kappa === nothing || softmin_kappa === :estimated
                (:estimated, exp(sk_lmean))
            elseif softmin_kappa isa Real && !(softmin_kappa isa Bool)
                (:fixed, _pos_real(softmin_kappa, "softmin_kappa"))
            else
                throw(ArgumentError("softmin_kappa must be nothing/:estimated or a finite positive real number; got $(repr(softmin_kappa))"))
            end
        end
        step_owner in (:item, :rater, :global) || throw(ArgumentError(
            "step_owner must be :item, :rater, or :global; got $(repr(step_owner))"))
        family_tag in (:mgmfrm, :gmfrm) || throw(ArgumentError(
            "family_tag must be :mgmfrm or :gmfrm; got $(repr(family_tag))"))
        item_role in (:item, :criterion) || throw(ArgumentError(
            "item_role must be :item or :criterion; got $(repr(item_role))"))
        if item_slopes === :fixed_one && scale_identification !== :geometric_mean_one
            throw(ArgumentError("item_slopes = :fixed_one requires scale_identification = :geometric_mean_one"))
        end

        (latent_correlation !== nothing && correlation !== nothing) && throw(ArgumentError(
            "supply either latent_correlation or correlation, not both"))
        corr_sym = if correlation !== nothing
            correlation === :independent ? :identity_fixed :
            correlation === :lkj ? :lkj :
            throw(ArgumentError("correlation must be :independent or :lkj; got $(repr(correlation))"))
        elseif latent_correlation !== nothing
            latent_correlation === :independent ? :identity_fixed : latent_correlation
        else
            :identity_fixed
        end
        corr_sym in (:identity_fixed, :lkj) || throw(ArgumentError(
            "latent_correlation must be :identity_fixed or :lkj; got $(repr(corr_sym))"))
        eta_val = _pos_real(lkj_eta, "lkj_eta")

        resolved_anchors = if scale_identification === :geometric_mean_one
            anchor_items === nothing || throw(ArgumentError(
                "anchor_items applies only when scale_identification = :anchor_item"))
            nothing
        else
            anchor_items === nothing ? :first_pure : deepcopy(anchor_items)
        end

        sd_fam, mu_sig, tau_sig, sd_sc, sd_df = _parse_sim_ability_sd_prior(
            ability_sd_prior, ability_logsd_prior, ability_logsd_mean, ability_logsd_sd)

        (log_loading_sd !== nothing && log_discrimination_sd !== nothing) && throw(ArgumentError(
            "supply either log_loading_sd or log_discrimination_sd, not both"))
        ll_sd = _pos_real(something(log_loading_sd, log_discrimination_sd, 0.5), "log_loading_sd")
        m_sd = _pos_real(ability_mean_sd, "ability_mean_sd")
        i_sd = _pos_real(item_sd, "item_sd")
        r_sd = _pos_real(rater_sd, "rater_sd")
        lc_sd = _pos_real(log_consistency_sd, "log_consistency_sd")
        st_sd = _pos_real(step_sd, "step_sd")

        return new(
            scale_identification,
            location_identification,
            s0,
            rater_consistency,
            resolved_anchors,
            mu_sig,
            tau_sig,
            m_sd,
            ll_sd,
            i_sd,
            r_sd,
            lc_sd,
            st_sd,
            sd_fam,
            sd_sc,
            sd_df,
            corr_sym,
            eta_val,
            item_slopes,
            item_slope_scope,
            step_owner,
            family_tag,
            item_role,
            rs_scope,
            aggregation,
            cl_avg,
            sk_mode,
            sk_val,
            sk_lmean,
            sk_lsd,
        )
    end

    function Prior(p::Prior; item_role::Symbol = p.item_role)
        item_role in (:item, :criterion) || throw(ArgumentError(
            "item_role must be :item or :criterion; got $(repr(item_role))"))
        return new(
            p.scale_identification, p.location_identification, p.logit_scale,
            p.rater_consistency, deepcopy(p.anchor_items), p.ability_logsd_mean,
            p.ability_logsd_sd, p.ability_mean_sd, p.log_loading_sd, p.item_sd,
            p.rater_sd, p.log_consistency_sd, p.step_sd, p.ability_sd_family,
            p.ability_sd_scale, p.ability_sd_df, p.latent_correlation, p.lkj_eta,
            p.item_slopes, p.item_slope_scope, p.step_owner, p.family_tag, item_role,
            p.rater_slope_scope, p.aggregation, p.cross_loading_average,
            p.softmin_kappa_mode, p.softmin_kappa, p.softmin_log_kappa_mean, p.softmin_log_kappa_sd,
        )
    end
end

function _with_item_role(p::Prior, item_role::Symbol)
    p.item_role === item_role && return p
    if item_role === :item && p.item_role === :criterion
        throw(ArgumentError("explicit prior has item_role = :criterion, which conflicts with facets declaring :item"))
    end
    return Prior(p; item_role)
end

@inline function _is_v1_compatible_prior(p::Prior)
    return p.ability_sd_family === :lognormal &&
           p.latent_correlation === :identity_fixed &&
           p.item_slopes === :estimated_positive &&
           p.item_slope_scope === :ability_only &&
           p.rater_slope_scope === :entire_linear_predictor &&
           p.aggregation === :additive &&
           !p.cross_loading_average &&
           p.step_owner === :item &&
           p.family_tag === :mgmfrm &&
           p.item_role === :item
end

function prior_record(p::Prior)
    anchors_rec = if p.anchor_items === nothing
        nothing
    elseif p.anchor_items isa Symbol
        p.anchor_items
    elseif p.anchor_items isa AbstractDict
        Pair[k => v for (k, v) in sort!(collect(pairs(p.anchor_items)); by = x -> string(first(x)))]
    elseif p.anchor_items isa NamedTuple
        p.anchor_items
    elseif p.anchor_items isa Union{AbstractVector, Tuple}
        collect(p.anchor_items)
    else
        p.anchor_items
    end
    base_nt = (;
        schema = PRIOR_SCHEMA,
        scale_identification = p.scale_identification,
        location_identification = p.location_identification,
        logit_scale = p.logit_scale,
        rater_consistency = p.rater_consistency,
        anchor_items = anchors_rec,
        ability_logsd_mean = p.ability_logsd_mean,
        ability_logsd_sd = p.ability_logsd_sd,
        ability_mean_sd = p.ability_mean_sd,
        log_loading_sd = p.log_loading_sd,
        item_sd = p.item_sd,
        rater_sd = p.rater_sd,
        log_consistency_sd = p.log_consistency_sd,
        step_sd = p.step_sd,
    )
    _is_v1_compatible_prior(p) && return base_nt
    return merge(base_nt, (;
        ability_sd_family = p.ability_sd_family,
        ability_sd_scale = p.ability_sd_scale,
        ability_sd_df = isfinite(p.ability_sd_df) ? p.ability_sd_df : "Inf",
        latent_correlation = p.latent_correlation,
        lkj_eta = p.lkj_eta,
        item_slopes = p.item_slopes,
        item_slope_scope = p.item_slope_scope,
        step_owner = p.step_owner,
        family_tag = p.family_tag,
        (p.item_role === :item ? (;) : (; item_role = p.item_role))...,
        (p.rater_slope_scope === :entire_linear_predictor ? (;) : (; rater_slope_scope = p.rater_slope_scope))...,
        (p.aggregation === :additive ? (;) : (;
            aggregation = p.aggregation,
            softmin_kappa_mode = p.softmin_kappa_mode,
            softmin_kappa = p.softmin_kappa,
            softmin_log_kappa_mean = p.softmin_log_kappa_mean,
            softmin_log_kappa_sd = p.softmin_log_kappa_sd,
        ))...,
        (p.cross_loading_average == (p.aggregation === :softmin) ? (;) : (; cross_loading_average = p.cross_loading_average))...,
    ))
end

function restore_prior(rec::NamedTuple)
    rec.schema == PRIOR_SCHEMA || throw(ArgumentError("unsupported scale-identified MGMFRM prior schema"))
    anc = rec.anchor_items isa AbstractVector{<:Pair} ? Dict(rec.anchor_items) : rec.anchor_items
    sd_fam = hasproperty(rec, :ability_sd_family) ? Symbol(rec.ability_sd_family) : :lognormal
    sd_pr = if sd_fam === :half_normal
        Truncated(Normal(0.0, Float64(rec.ability_sd_scale)), 0.0, Inf)
    elseif sd_fam === :half_t
        df_v = rec.ability_sd_df isa AbstractString ? parse(Float64, rec.ability_sd_df) : Float64(rec.ability_sd_df)
        Truncated(LocationScale(0.0, Float64(rec.ability_sd_scale), TDist(df_v)), 0.0, Inf)
    else
        nothing
    end
    agg_sym = hasproperty(rec, :aggregation) ? Symbol(rec.aggregation) : :additive
    sk_mode = hasproperty(rec, :softmin_kappa_mode) ? Symbol(rec.softmin_kappa_mode) : (agg_sym === :softmin ? :estimated : :none)
    sk_arg = agg_sym === :additive ? nothing : (sk_mode === :fixed ? Float64(rec.softmin_kappa) : :estimated)
    return Prior(;
        scale_identification = Symbol(rec.scale_identification),
        location_identification = Symbol(rec.location_identification),
        logit_scale = Float64(rec.logit_scale),
        rater_consistency = Symbol(rec.rater_consistency),
        anchor_items = rec.scale_identification === :geometric_mean_one ? nothing : anc,
        ability_sd_prior = sd_pr,
        ability_logsd_mean = sd_pr === nothing ? Float64(rec.ability_logsd_mean) : nothing,
        ability_logsd_sd = sd_pr === nothing ? Float64(rec.ability_logsd_sd) : nothing,
        ability_mean_sd = Float64(rec.ability_mean_sd),
        log_loading_sd = Float64(rec.log_loading_sd),
        item_sd = Float64(rec.item_sd),
        rater_sd = Float64(rec.rater_sd),
        log_consistency_sd = Float64(rec.log_consistency_sd),
        step_sd = Float64(rec.step_sd),
        latent_correlation = hasproperty(rec, :latent_correlation) ? Symbol(rec.latent_correlation) : :identity_fixed,
        lkj_eta = hasproperty(rec, :lkj_eta) ? Float64(rec.lkj_eta) : 2.0,
        item_slopes = hasproperty(rec, :item_slopes) ? Symbol(rec.item_slopes) : :estimated_positive,
        item_slope_scope = hasproperty(rec, :item_slope_scope) ? Symbol(rec.item_slope_scope) : :ability_only,
        step_owner = hasproperty(rec, :step_owner) ? Symbol(rec.step_owner) : :item,
        family_tag = hasproperty(rec, :family_tag) ? Symbol(rec.family_tag) : :mgmfrm,
        item_role = hasproperty(rec, :item_role) ? Symbol(rec.item_role) : :item,
        rater_slope_scope = hasproperty(rec, :rater_slope_scope) ? Symbol(rec.rater_slope_scope) : :entire_linear_predictor,
        aggregation = agg_sym,
        cross_loading_average = hasproperty(rec, :cross_loading_average) ? Bool(rec.cross_loading_average) : nothing,
        softmin_kappa = sk_arg,
        softmin_log_kappa_mean = hasproperty(rec, :softmin_log_kappa_mean) ? Float64(rec.softmin_log_kappa_mean) : 0.0,
        softmin_log_kappa_sd = hasproperty(rec, :softmin_log_kappa_sd) ? Float64(rec.softmin_log_kappa_sd) : 1.0,
    )
end

struct Target <: B.AbstractMFRMSpec
    spec::B.FacetSpec
    prior::Prior
    P::Int
    I::Int
    R::Int
    D::Int
    K::Int
    H::Int
    N::Int
    person::Vector{Int}
    item::Vector{Int}
    rater::Vector{Int}
    category::Vector{Int}
    person_levels::Vector{Any}
    item_levels::Vector{Any}
    rater_levels::Vector{Any}
    category_levels::Vector{Int}
    dimension_labels::Vector{String}
    q_matrix::Matrix{Bool}
    active_dims_of_item::Vector{Vector{Int}}
    active_pairs::Vector{Tuple{Int,Int}}
    pure_items_by_dim::Vector{Vector{Int}}
    cross_items::Vector{Int}
    cross_loading_pairs::Vector{Tuple{Int,Int}}
    anchor_item_indices::Vector{Int}
    anchor_free_loading_pairs::Vector{Tuple{Int,Int}}
    step_owner::Symbol
    n_step_groups::Int
    step_group_of_obs::Vector{Int}
    step_group_levels::Vector{Any}
    person_z_range::UnitRange{Int}
    ability_mean_z_range::UnitRange{Int}
    ability_logsd_z_range::UnitRange{Int}
    pure_loading_ranges::Vector{UnitRange{Int}}
    cross_loading_range::UnitRange{Int}
    anchor_free_loading_range::UnitRange{Int}
    item_free_range::UnitRange{Int}
    pure_item_ranges::Vector{UnitRange{Int}}
    cross_item_range::UnitRange{Int}
    rater_range::UnitRange{Int}
    consistency_range::UnitRange{Int}
    step_ranges::Vector{UnitRange{Int}}
    corr_z_range::UnitRange{Int}
    softmin_kappa_z_range::UnitRange{Int}
    lkj_alphas::Vector{Float64}
    lkj_log_normalizer::Float64
    pure_loading_scales::Vector{Float64}
    pure_item_scales::Vector{Float64}
    rater_scale::Float64
    consistency_scale::Float64
    step_scale::Float64
    dimension::Int
    raw_names::Vector{String}
    model_names::Vector{String}
    fixed_model_names::Set{String}
end

struct Fit <: B.AbstractMFRMFit
    record::NamedTuple
end

function Base.show(io::IO, p::Prior)
    print(io, "ScaleIdentifiedMGMFRMPrior(",
        p.scale_identification, ", location=", p.location_identification,
        ", correlation=", p.latent_correlation,
        ", logit_scale=", p.logit_scale,
        ", log_loading_sd=", p.log_loading_sd, ")")
end

function Base.show(io::IO, t::Target)
    print(io, "ScaleIdentifiedMGMFRMTarget(family=", t.prior.family_tag,
        ", D=", t.D,
        ", scale=", t.prior.scale_identification,
        ", location=", t.prior.location_identification,
        ", correlation=", t.prior.latent_correlation,
        ", steps=", t.step_owner,
        ", params=", t.dimension, ", N=", t.N, ")")
end

function Base.show(io::IO, f::Fit)
    r = f.record
    fam = hasproperty(r.target.prior, :family_tag) ? Symbol(r.target.prior.family_tag) : :mgmfrm
    print(io, "ScaleIdentifiedMGMFRMFit(",
        fam, ", ", r.target.prior.scale_identification,
        "; ", r.run.total_draws, " retained draws across ",
        r.run.controls.chains, " chains)")
end

function _resolve_item_index(item_levels::AbstractVector, candidate, d::Int)
    idx = findfirst(x -> isequal(x, candidate), item_levels)
    idx !== nothing && return idx
    if candidate isa Symbol
        idx_s = findfirst(x -> string(x) == String(candidate), item_levels)
        idx_s !== nothing && return idx_s
    elseif candidate isa AbstractString
        idx_s = findfirst(x -> string(x) == candidate, item_levels)
        idx_s !== nothing && return idx_s
    elseif candidate isa Integer && !(candidate isa Bool) && !any(x -> x isa Integer, item_levels) &&
           1 <= Int(candidate) <= length(item_levels)
        return Int(candidate)
    end
    throw(ArgumentError("anchor item $(repr(candidate)) for dimension $d is absent from item_levels $(item_levels)"))
end

function _resolve_anchor_items(
        anchor_spec,
        D::Int,
        dimension_labels::AbstractVector,
        item_levels::AbstractVector,
        pure_items_by_dim::Vector{Vector{Int}})
    if anchor_spec === :first_pure
        return [first(pure_items_by_dim[d]) for d in 1:D]
    elseif anchor_spec isa Union{AbstractVector, Tuple}
        length(anchor_spec) == D || throw(ArgumentError(
            "anchor_items vector/tuple must have length D = $D; got $(length(anchor_spec))"))
        out = Vector{Int}(undef, D)
        for d in 1:D
            idx = _resolve_item_index(item_levels, anchor_spec[d], d)
            idx in pure_items_by_dim[d] || throw(ArgumentError(
                "anchor item $(repr(item_levels[idx])) for dimension $d is not a pure item on dimension $d"))
            out[d] = idx
        end
        return out
    elseif anchor_spec isa Union{AbstractDict, NamedTuple}
        out = zeros(Int, D)
        kv_pairs = anchor_spec isa NamedTuple ? collect(pairs(anchor_spec)) : collect(anchor_spec)
        length(kv_pairs) == D || throw(ArgumentError(
            "anchor_items mapping must specify exactly one pure item for each of the $D dimensions"))
        for (k, v) in kv_pairs
            d_idx = if k isa Integer && !(k isa Bool) && 1 <= Int(k) <= D
                Int(k)
            else
                ks = string(k)
                found_d = findfirst(l -> string(l) == ks, dimension_labels)
                if found_d === nothing && startswith(ks, "dim")
                    parsed = tryparse(Int, replace(ks, r"^dim_?" => ""))
                    (parsed !== nothing && 1 <= parsed <= D) && (found_d = parsed)
                end
                found_d === nothing && throw(ArgumentError(
                    "unrecognized dimension key $(repr(k)) in anchor_items; expected 1..$D or $(dimension_labels)"))
                found_d
            end
            out[d_idx] == 0 || throw(ArgumentError("duplicate anchor item specification for dimension $d_idx"))
            idx = _resolve_item_index(item_levels, v, d_idx)
            idx in pure_items_by_dim[d_idx] || throw(ArgumentError(
                "anchor item $(repr(item_levels[idx])) for dimension $d_idx is not a pure item on dimension $d_idx"))
            out[d_idx] = idx
        end
        return out
    else
        throw(ArgumentError(
            "anchor_items must be :first_pure, a length-D Vector/Tuple, or a Dict/NamedTuple mapping each dimension to a pure item"))
    end
end

function model(spec::B.FacetSpec; prior::Prior = Prior())
    spec.family === :mgmfrm || throw(ArgumentError(
        "ScaleIdentifiedMGMFRM requires a FacetSpec with family = :mgmfrm; got family = $(repr(spec.family))"))
    (spec.thresholds === :partial_credit ||
     (spec.thresholds === :rating_scale && prior.step_owner === :global)) || throw(ArgumentError(
        "ScaleIdentifiedMGMFRM requires partial_credit thresholds in FacetSpec (or rating_scale with step_owner = :global); got $(repr(spec.thresholds))"))
    isempty(spec.validation_bias_terms) || throw(ArgumentError(
        "ScaleIdentifiedMGMFRM does not accept fitted interaction validation_bias_terms in FacetSpec"))
    isempty(spec.anchors) || throw(ArgumentError(
        "ScaleIdentifiedMGMFRM manages location and scale identification via ScaleIdentifiedMGMFRMPrior; FacetSpec anchors must be empty"))

    spec_copy = deepcopy(spec)
    data = spec_copy.data
    P = length(data.person_levels)
    I = length(data.item_levels)
    R = length(data.rater_levels)
    D = spec_copy.dimensions
    K = length(data.category_levels)
    H = K - 1
    N = data.n
    K >= 2 || throw(ArgumentError("at least 2 score categories are required; got K = $K"))
    D >= 1 || throw(ArgumentError("dimensions D must be >= 1; got D = $D"))
    if prior.item_slope_scope === :entire_linear_predictor && D != 1
        throw(ArgumentError("item_slope_scope = :entire_linear_predictor applies only to 1D (D = 1) models"))
    end
    if prior.family_tag === :gmfrm && D != 1
        throw(ArgumentError("GMFRM requires D = 1; got D = $D"))
    end

    q_raw = spec_copy.q_matrix
    q_raw !== nothing && size(q_raw) == (I, D) || throw(ArgumentError(
        "FacetSpec q_matrix must have size ($I, $D)"))
    q_mat = Bool.(q_raw)

    active_dims_of_item = [findall(view(q_mat, i, :)) for i in 1:I]
    any(isempty, active_dims_of_item) && throw(ArgumentError(
        "every item row of q_matrix must load on at least one dimension"))

    pure_items_by_dim = [Int[] for _ in 1:D]
    cross_items = Int[]
    for i in 1:I
        ad = active_dims_of_item[i]
        if length(ad) == 1
            push!(pure_items_by_dim[only(ad)], i)
        else
            push!(cross_items, i)
        end
    end
    for d in 1:D
        !isempty(pure_items_by_dim[d]) || throw(ArgumentError(
            "multiplicative scale identification requires at least 1 pure item in every dimension; dimension $d ($(repr(spec_copy.dimension_labels[d]))) has 0 pure items"))
    end
    if prior.aggregation === :softmin
        D >= 2 || throw(ArgumentError("aggregation = :softmin requires a multidimensional model (D >= 2)"))
        !isempty(cross_items) || throw(ArgumentError(
            "aggregation = :softmin requires at least one cross-loaded item (sum(Q[i, :]) >= 2); for between-item Q-matrices each item loads on a single dimension so compensatory and noncompensatory kernels coincide"))
        prior.item_slope_scope === :ability_only || throw(ArgumentError(
            "aggregation = :softmin requires item_slope_scope = :ability_only"))
    end

    if prior.latent_correlation === :lkj
        (2 <= D <= 3) || throw(ArgumentError(
            "LKJ latent correlation in ScaleIdentifiedMGMFRM requires D in {2, 3}; got D = $D"))
        all(d -> length(pure_items_by_dim[d]) >= 2, 1:D) || throw(ArgumentError(
            "LKJ latent correlation requires at least 2 pure items per dimension; got $(Tuple(length.(pure_items_by_dim)))"))
        obs_pd = falses(P, D)
        for n in 1:N
            p_n = data.person[n]
            for d in active_dims_of_item[data.item[n]]
                obs_pd[p_n, d] = true
            end
        end
        all(obs_pd) || throw(ArgumentError(
            "LKJ latent correlation requires every person to have at least one observation connected to every dimension 1..$D"))
    end

    active_pairs = Tuple{Int,Int}[(i, d) for i in 1:I for d in active_dims_of_item[i]]
    cross_set = Set(cross_items)
    cross_loading_pairs = prior.item_slopes === :fixed_one ? Tuple{Int,Int}[] :
        Tuple{Int,Int}[(i, d) for (i, d) in active_pairs if i in cross_set]

    anchor_item_indices = prior.scale_identification === :anchor_item ?
        _resolve_anchor_items(prior.anchor_items, D, spec_copy.dimension_labels, data.item_levels, pure_items_by_dim) :
        Int[]
    anchor_pair_set = Set{Tuple{Int,Int}}((anchor_item_indices[d], d) for d in eachindex(anchor_item_indices))
    anchor_free_loading_pairs = (prior.scale_identification === :anchor_item && prior.item_slopes === :estimated_positive) ?
        Tuple{Int,Int}[(i, d) for (i, d) in active_pairs if !((i, d) in anchor_pair_set)] :
        Tuple{Int,Int}[]

    step_owner = prior.step_owner
    n_step_groups, step_group_of_obs, step_group_levels = if step_owner === :item
        (I, copy(data.item), deepcopy(data.item_levels))
    elseif step_owner === :rater
        (R, copy(data.rater), deepcopy(data.rater_levels))
    else
        (1, ones(Int, N), Any[:global])
    end

    raw_names = String[]
    cursor = 0

    # 1. Non-centered person white coordinates z_{p, d} ~ N(0, 1)
    person_z_range = (cursor + 1):(cursor + P * D)
    for p in 1:P, d in 1:D
        push!(raw_names, "person_z[$(_fmt_label(data.person_levels[p])), dim=$d]")
    end
    cursor += P * D

    # 2. Population ability mean coordinates (when :centered_items_free_mean)
    ability_mean_z_range = if prior.location_identification === :centered_items_free_mean
        rng = (cursor + 1):(cursor + D)
        for d in 1:D
            push!(raw_names, "ability_mean_z[dim=$d]")
        end
        cursor += D
        rng
    else
        (cursor + 1):cursor
    end

    # 3. Population ability log-SD coordinates
    ability_logsd_z_range = (cursor + 1):(cursor + D)
    for d in 1:D
        push!(raw_names, "ability_logsd_z[dim=$d]")
    end
    cursor += D

    # 4. Loading coordinates
    pure_loading_ranges = Vector{UnitRange{Int}}(undef, D)
    pure_loading_scales = zeros(Float64, D)
    if prior.item_slopes === :fixed_one
        for d in 1:D
            pure_loading_ranges[d] = (cursor + 1):cursor
        end
        cross_loading_range = (cursor + 1):cursor
        anchor_free_loading_range = (cursor + 1):cursor
    elseif prior.scale_identification === :geometric_mean_one
        for d in 1:D
            Id = length(pure_items_by_dim[d])
            if Id >= 2
                pure_loading_ranges[d] = (cursor + 1):(cursor + Id - 1)
                pure_loading_scales[d] = prior.log_loading_sd * sqrt(Float64(Id) / Float64(Id - 1))
                for k in 1:(Id - 1)
                    push!(raw_names, "loading_contrast[dim=$d, k=$k]")
                end
                cursor += Id - 1
            else
                pure_loading_ranges[d] = (cursor + 1):cursor
            end
        end
        n_cl = length(cross_loading_pairs)
        cross_loading_range = (cursor + 1):(cursor + n_cl)
        for (i, d) in cross_loading_pairs
            push!(raw_names, "log_loading_z[$(_fmt_label(data.item_levels[i])), dim=$d]")
        end
        cursor += n_cl
        anchor_free_loading_range = (cursor + 1):cursor
    else
        for d in 1:D
            pure_loading_ranges[d] = (cursor + 1):cursor
        end
        cross_loading_range = (cursor + 1):cursor
        n_fl = length(anchor_free_loading_pairs)
        anchor_free_loading_range = (cursor + 1):(cursor + n_fl)
        for (i, d) in anchor_free_loading_pairs
            push!(raw_names, "log_loading_z[$(_fmt_label(data.item_levels[i])), dim=$d]")
        end
        cursor += n_fl
    end

    # 5. Item difficulty coordinates
    pure_item_ranges = Vector{UnitRange{Int}}(undef, D)
    pure_item_scales = zeros(Float64, D)
    if prior.location_identification === :zero_mean_population
        item_free_range = (cursor + 1):(cursor + I)
        for i in 1:I
            push!(raw_names, "item_z[$(_fmt_label(data.item_levels[i]))]")
        end
        cursor += I
        for d in 1:D
            pure_item_ranges[d] = (cursor + 1):cursor
        end
        cross_item_range = (cursor + 1):cursor
    else
        item_free_range = (cursor + 1):cursor
        for d in 1:D
            Id = length(pure_items_by_dim[d])
            if Id >= 2
                pure_item_ranges[d] = (cursor + 1):(cursor + Id - 1)
                pure_item_scales[d] = prior.item_sd * sqrt(Float64(Id) / Float64(Id - 1))
                for k in 1:(Id - 1)
                    push!(raw_names, "item_contrast[dim=$d, k=$k]")
                end
                cursor += Id - 1
            else
                pure_item_ranges[d] = (cursor + 1):cursor
            end
        end
        n_ci = length(cross_items)
        cross_item_range = (cursor + 1):(cursor + n_ci)
        for i in cross_items
            push!(raw_names, "item_z[$(_fmt_label(data.item_levels[i]))]")
        end
        cursor += n_ci
    end

    # 6. Isometric rater severities
    if R >= 2
        rater_range = (cursor + 1):(cursor + R - 1)
        rater_scale = prior.rater_sd * sqrt(Float64(R) / Float64(R - 1))
        for k in 1:(R - 1)
            push!(raw_names, "rater_contrast[k=$k]")
        end
        cursor += R - 1
    else
        rater_range = (cursor + 1):cursor
        rater_scale = 0.0
    end

    # 7. Isometric log rater consistencies
    if prior.rater_consistency === :estimated_positive && R >= 2
        consistency_range = (cursor + 1):(cursor + R - 1)
        consistency_scale = prior.log_consistency_sd * sqrt(Float64(R) / Float64(R - 1))
        for k in 1:(R - 1)
            push!(raw_names, "consistency_contrast[k=$k]")
        end
        cursor += R - 1
    else
        consistency_range = (cursor + 1):cursor
        consistency_scale = 0.0
    end

    # 8. Isometric steps (by step_owner: :item, :rater, or :global)
    step_ranges = Vector{UnitRange{Int}}(undef, n_step_groups)
    step_scale = H >= 2 ? prior.step_sd * sqrt(Float64(H) / Float64(H - 1)) : 0.0
    for g in 1:n_step_groups
        if H >= 2
            step_ranges[g] = (cursor + 1):(cursor + H - 1)
            g_lbl = step_owner === :global ? "global" : _fmt_label(step_group_levels[g])
            for k in 1:(H - 1)
                push!(raw_names, "step_contrast[$g_lbl, k=$k]")
            end
            cursor += H - 1
        else
            step_ranges[g] = (cursor + 1):cursor
        end
    end

    # 9. Optional Cholesky-factor Fisher-z LKJ partial-correlation coordinates (Stan row-major order)
    lkj_alphas = Float64[]
    lkj_log_normalizer = 0.0
    if prior.latent_correlation === :lkj
        n_corr = (D * (D - 1)) ÷ 2
        corr_z_range = (cursor + 1):(cursor + n_corr)
        for i in 2:D, j in 1:(i - 1)
            alpha_j = prior.lkj_eta + 0.5 * Float64(D - 1 - j)
            push!(lkj_alphas, alpha_j)
            lkj_log_normalizer -= SpecialFunctions.logbeta(0.5, alpha_j)
            push!(raw_names, "corr_z[dim=$j, dim=$i]")
        end
        cursor += n_corr
    else
        corr_z_range = (cursor + 1):cursor
    end

    # 10. Optional smooth bottleneck noncompensatory curvature coordinate
    if prior.softmin_kappa_mode === :estimated
        softmin_kappa_z_range = (cursor + 1):(cursor + 1)
        push!(raw_names, "softmin_log_kappa_z")
        cursor += 1
    else
        softmin_kappa_z_range = (cursor + 1):cursor
    end

    # Model-space names and structurally fixed set
    model_names = String[]
    fixed_model_names = Set{String}()

    for p in 1:P, d in 1:D
        push!(model_names, "person[$(_fmt_label(data.person_levels[p])), dim=$d]")
    end
    for d in 1:D
        nm = "ability_mean[dim=$d]"
        push!(model_names, nm)
        prior.location_identification === :zero_mean_population && push!(fixed_model_names, nm)
    end
    for d in 1:D
        push!(model_names, "ability_sd[dim=$d]")
    end
    for (i, d) in active_pairs
        nm = "loading[$(_fmt_label(data.item_levels[i])), dim=$d]"
        push!(model_names, nm)
        if prior.item_slopes === :fixed_one
            push!(fixed_model_names, nm)
        elseif prior.scale_identification === :anchor_item && i == anchor_item_indices[d]
            push!(fixed_model_names, nm)
        elseif prior.scale_identification === :geometric_mean_one &&
               length(active_dims_of_item[i]) == 1 && length(pure_items_by_dim[d]) == 1
            push!(fixed_model_names, nm)
        end
    end
    for (i, d) in active_pairs
        push!(model_names, "standardized_loading[$(_fmt_label(data.item_levels[i])), dim=$d]")
    end
    for i in 1:I
        nm = "item[$(_fmt_label(data.item_levels[i]))]"
        push!(model_names, nm)
        if prior.location_identification === :centered_items_free_mean &&
           length(active_dims_of_item[i]) == 1 && length(pure_items_by_dim[only(active_dims_of_item[i])]) == 1
            push!(fixed_model_names, nm)
        end
    end
    for r in 1:R
        nm = "rater[$(_fmt_label(data.rater_levels[r]))]"
        push!(model_names, nm)
        R == 1 && push!(fixed_model_names, nm)
    end
    for r in 1:R
        nm = "consistency[$(_fmt_label(data.rater_levels[r]))]"
        push!(model_names, nm)
        (prior.rater_consistency === :fixed_one || R == 1) && push!(fixed_model_names, nm)
    end
    for g in 1:n_step_groups, m in 1:H
        g_lbl = step_owner === :global ? "global" : _fmt_label(step_group_levels[g])
        nm = "step[$g_lbl, $m]"
        push!(model_names, nm)
        H == 1 && push!(fixed_model_names, nm)
    end
    if prior.latent_correlation === :lkj
        for i in 2:D, j in 1:(i - 1)
            push!(model_names, "latent_correlation[dim=$j, dim=$i]")
        end
        if D == 3
            push!(model_names, "partial_correlation[dim=2, dim=3 | dim=1]")
        end
    end
    if prior.aggregation === :softmin
        push!(model_names, "softmin_kappa")
        prior.softmin_kappa_mode === :fixed && push!(fixed_model_names, "softmin_kappa")
    end

    return Target(
        spec_copy,
        prior,
        P, I, R, D, K, H, N,
        copy(data.person),
        copy(data.item),
        copy(data.rater),
        copy(data.category),
        deepcopy(data.person_levels),
        deepcopy(data.item_levels),
        deepcopy(data.rater_levels),
        copy(data.category_levels),
        copy(spec_copy.dimension_labels),
        q_mat,
        active_dims_of_item,
        active_pairs,
        pure_items_by_dim,
        cross_items,
        cross_loading_pairs,
        anchor_item_indices,
        anchor_free_loading_pairs,
        step_owner,
        n_step_groups,
        step_group_of_obs,
        step_group_levels,
        person_z_range,
        ability_mean_z_range,
        ability_logsd_z_range,
        pure_loading_ranges,
        cross_loading_range,
        anchor_free_loading_range,
        item_free_range,
        pure_item_ranges,
        cross_item_range,
        rater_range,
        consistency_range,
        step_ranges,
        corr_z_range,
        softmin_kappa_z_range,
        lkj_alphas,
        lkj_log_normalizer,
        pure_loading_scales,
        pure_item_scales,
        rater_scale,
        consistency_scale,
        step_scale,
        cursor,
        raw_names,
        model_names,
        fixed_model_names,
    )
end

function gmfrm_model(
        fd::B.FacetData;
        prior::Union{Nothing, Prior} = nothing,
        slope::Symbol = :rater,
        steps::Symbol = :rater,
        logit_scale::Real = 1.0,
        scale_identification::Symbol = :geometric_mean_one,
        anchor_items = nothing,
        location_identification::Symbol = :centered_items_free_mean,
        rater_slope_scope::Symbol = :entire_linear_predictor,
        ability_sd_prior = Truncated(Normal(0.0, 1.0), 0.0, Inf),
        ability_mean_sd::Real = 2.5,
        slope_sd::Real = 0.35,
        log_loading_sd::Union{Nothing, Real} = nothing,
        log_consistency_sd::Union{Nothing, Real} = nothing,
        item_sd::Real = 1.0,
        rater_sd::Real = 1.0,
        step_sd::Real = 1.0,
        item_role::Symbol = :item)
    slope in (:rater, :item, :both) || throw(ArgumentError(
        "GMFRM slope must be :rater, :item, or :both; got $(repr(slope))"))
    steps in (:global, :item, :rater) || throw(ArgumentError(
        "GMFRM steps must be :global, :item, or :rater; got $(repr(steps))"))
    rs_norm = rater_slope_scope === :linear_predictor ? :entire_linear_predictor : rater_slope_scope
    if slope === :item && rs_norm === :ability_only
        throw(ArgumentError("rater_slope_scope = :ability_only requires estimated rater slopes (slope = :rater or :both)"))
    end
    I = length(fd.item_levels)
    sp = B.mfrm_spec(fd;
        family = :mgmfrm,
        dimensions = 1,
        thresholds = :partial_credit,
        q_matrix = trues(I, 1),
        dimension_labels = ["Trait1"],
    )
    if prior !== nothing
        return model(sp; prior = _with_item_role(prior, item_role))
    end
    it_slopes = slope === :rater ? :fixed_one : :estimated_positive
    rt_cons = slope === :item ? :fixed_one : :estimated_positive
    it_scope = slope === :item ? :entire_linear_predictor : :ability_only
    pr = Prior(;
        scale_identification,
        anchor_items,
        location_identification,
        logit_scale,
        rater_consistency = rt_cons,
        rater_slope_scope = rs_norm,
        ability_sd_prior,
        ability_mean_sd,
        log_loading_sd = something(log_loading_sd, slope_sd),
        item_sd,
        rater_sd,
        log_consistency_sd = something(log_consistency_sd, slope_sd),
        step_sd,
        item_slopes = it_slopes,
        item_slope_scope = it_scope,
        step_owner = steps,
        family_tag = :gmfrm,
        item_role,
    )
    return model(sp; prior = pr)
end

function target_record(t::Target)
    return (;
        schema = TARGET_SCHEMA,
        spec = t.spec,
        prior = prior_record(t.prior),
        data_signature = t.spec.validation.data_signature,
    )
end

target_identity(t::Target) = B._cache_hash((;
    schema = TARGET_SCHEMA,
    design = B.design_identity(B.getdesign(t.spec; preview = true)).value,
    prior = prior_record(t.prior),
))

function restore_target(rec::NamedTuple)
    rec.schema == TARGET_SCHEMA || throw(ArgumentError("unsupported scale-identified MGMFRM target schema"))
    p = restore_prior(rec.prior)
    t = model(rec.spec; prior = p)
    t.spec.validation.data_signature == rec.data_signature ||
        throw(ArgumentError("scale-identified MGMFRM target data signature mismatch"))
    return t
end

# ---------------------------------------------------------------------------
# Isometric Orthonormal Helmert Forward & Reverse-Mode Pullback Operators
# ---------------------------------------------------------------------------

@inline function _helmert_zero_sum!(out::AbstractVector{T}, v::AbstractVector, scale::Float64) where {T}
    m = length(v)
    @assert length(out) == m + 1
    tail = zero(T)
    @inbounds for j in m:-1:1
        val = v[j] / sqrt(Float64(j) * Float64(j + 1))
        out[j + 1] = scale * (tail - Float64(j) * val)
        tail += val
    end
    @inbounds out[1] = scale * tail
    return out
end

@inline function _helmert_zero_sum_pullback!(
        g_q::AbstractVector{T},
        q_slice::AbstractVector,
        g_out::AbstractVector{T},
        scale::Float64) where {T}
    m = length(q_slice)
    @assert length(g_q) == m && length(g_out) == m + 1
    pref = g_out[1]
    @inbounds for k in 1:m
        g_q[k] = scale * ((pref - Float64(k) * g_out[k + 1]) / sqrt(Float64(k) * Float64(k + 1))) - q_slice[k]
        pref += g_out[k + 1]
    end
    return g_q
end

L.dimension(t::Target) = t.dimension
L.capabilities(::Type{Target}) = L.LogDensityOrder{1}()

function _check_vector(t::Target, q::AbstractVector; finite::Bool = true)
    length(q) == t.dimension ||
        throw(ArgumentError("expected $(t.dimension) unconstrained coordinates; got $(length(q))"))
    finite && !all(isfinite, q) &&
        throw(ArgumentError("unconstrained parameter coordinates must be finite"))
    return nothing
end

B._check_source_fixture_raw_vector(t::Target, q::AbstractVector) = _check_vector(t, q)

# ---------------------------------------------------------------------------
# Coordinate Reconstruction & Exact Subspace/Positive Jacobian Accounting
# ---------------------------------------------------------------------------

function coordinates(t::Target, q::AbstractVector{<:Real})
    _check_vector(t, q)
    Z = promote_type(Float64, eltype(q))
    pr = t.prior
    P, I, R, D, H = t.P, t.I, t.R, t.D, t.H
    G_step = t.n_step_groups

    person_z = Matrix{Z}(undef, P, D)
    idx = 0
    @inbounds for p in 1:P, d in 1:D
        idx += 1
        person_z[p, d] = q[idx]
    end

    ability_mean = zeros(Z, D)
    log_jac = zero(Z)
    if pr.location_identification === :centered_items_free_mean
        @inbounds for d in 1:D
            ability_mean[d] = pr.ability_mean_sd * q[t.ability_mean_z_range[d]]
        end
        log_jac += D * log(pr.ability_mean_sd)
    end

    ability_logsd = Vector{Z}(undef, D)
    ability_sd = Vector{Z}(undef, D)
    if pr.ability_sd_family === :lognormal
        @inbounds for d in 1:D
            lsd = pr.ability_logsd_mean + pr.ability_logsd_sd * q[t.ability_logsd_z_range[d]]
            ability_logsd[d] = lsd
            ability_sd[d] = exp(lsd)
            log_jac += log(pr.ability_logsd_sd) + lsd
        end
    else
        @inbounds for d in 1:D
            lsd = Z(q[t.ability_logsd_z_range[d]])
            ability_logsd[d] = lsd
            ability_sd[d] = exp(lsd)
            log_jac += lsd
        end
    end

    cholesky_L = zeros(Z, D, D)
    partial_correlations = Vector{Z}(undef, length(t.corr_z_range))
    log_lkj_kernel = zero(Z)
    if pr.latent_correlation === :lkj
        cholesky_L[1, 1] = one(Z)
        k_c = 0
        for i_d in 2:D
            log_rem = zero(Z)
            for j_d in 1:(i_d - 1)
                k_c += 1
                qk = q[t.corr_z_range[k_c]]
                z_ij = tanh(qk)
                partial_correlations[k_c] = z_ij
                log_delta = _logsech2(qk)
                cholesky_L[i_d, j_d] = z_ij * exp(0.5 * log_rem)
                log_jac += log_delta + 0.5 * log_rem
                log_rem += log_delta
            end
            cholesky_L[i_d, i_d] = exp(0.5 * log_rem)
            cholesky_L[i_d, i_d] > zero(Z) || throw(DomainError(0.0, "Cholesky diagonal underflow"))
            log_lkj_kernel += 0.5 * (Float64(D - i_d) + 2.0 * pr.lkj_eta - 2.0) * log_rem
        end
    else
        @inbounds for d in 1:D
            cholesky_L[d, d] = one(Z)
        end
    end
    correlation_matrix = cholesky_L * transpose(cholesky_L)

    person = Matrix{Z}(undef, P, D)
    if pr.latent_correlation === :lkj
        @inbounds for p in 1:P
            for i_d in 1:D
                u_pi = zero(Z)
                for j_d in 1:i_d
                    u_pi += cholesky_L[i_d, j_d] * person_z[p, j_d]
                end
                person[p, i_d] = ability_mean[i_d] + ability_sd[i_d] * u_pi
            end
        end
    else
        @inbounds for d in 1:D
            mu_d = ability_mean[d]
            sd_d = ability_sd[d]
            for p in 1:P
                person[p, d] = mu_d + sd_d * person_z[p, d]
            end
        end
    end

    log_loading = zeros(Z, I, D)
    loading = zeros(Z, I, D)
    standardized_loading = zeros(Z, I, D)
    if pr.item_slopes === :fixed_one
        # All active item loadings fixed to 1.0 (log_loading == 0.0)
    elseif pr.scale_identification === :geometric_mean_one
        for d in 1:D
            pitems = t.pure_items_by_dim[d]
            Id = length(pitems)
            if Id >= 2
                tmp = Vector{Z}(undef, Id)
                _helmert_zero_sum!(tmp, view(q, t.pure_loading_ranges[d]), t.pure_loading_scales[d])
                for (m, i) in enumerate(pitems)
                    log_loading[i, d] = tmp[m]
                end
                log_jac += (Id - 1) * log(t.pure_loading_scales[d])
            else
                log_loading[only(pitems), d] = zero(Z)
            end
        end
        for (m, (i, d)) in enumerate(t.cross_loading_pairs)
            ll = pr.log_loading_sd * q[t.cross_loading_range[m]]
            log_loading[i, d] = ll
            log_jac += log(pr.log_loading_sd) + ll
        end
    else
        for d in 1:D
            log_loading[t.anchor_item_indices[d], d] = zero(Z)
        end
        for (m, (i, d)) in enumerate(t.anchor_free_loading_pairs)
            ll = pr.log_loading_sd * q[t.anchor_free_loading_range[m]]
            log_loading[i, d] = ll
            log_jac += log(pr.log_loading_sd) + ll
        end
    end
    @inbounds for (i, d) in t.active_pairs
        a_val = exp(log_loading[i, d])
        loading[i, d] = a_val
        standardized_loading[i, d] = a_val * ability_sd[d]
    end

    item = zeros(Z, I)
    if pr.location_identification === :zero_mean_population
        @inbounds for i in 1:I
            item[i] = pr.item_sd * q[t.item_free_range[i]]
        end
        log_jac += I * log(pr.item_sd)
    else
        for d in 1:D
            pitems = t.pure_items_by_dim[d]
            Id = length(pitems)
            if Id >= 2
                tmp = Vector{Z}(undef, Id)
                _helmert_zero_sum!(tmp, view(q, t.pure_item_ranges[d]), t.pure_item_scales[d])
                for (m, i) in enumerate(pitems)
                    item[i] = tmp[m]
                end
                log_jac += (Id - 1) * log(t.pure_item_scales[d])
            else
                item[only(pitems)] = zero(Z)
            end
        end
        for (m, i) in enumerate(t.cross_items)
            item[i] = pr.item_sd * q[t.cross_item_range[m]]
        end
        !isempty(t.cross_items) && (log_jac += length(t.cross_items) * log(pr.item_sd))
    end

    rater = zeros(Z, R)
    if R >= 2
        _helmert_zero_sum!(rater, view(q, t.rater_range), t.rater_scale)
        log_jac += (R - 1) * log(t.rater_scale)
    end

    log_consistency = zeros(Z, R)
    consistency = ones(Z, R)
    if pr.rater_consistency === :estimated_positive && R >= 2
        _helmert_zero_sum!(log_consistency, view(q, t.consistency_range), t.consistency_scale)
        @inbounds for r in 1:R
            consistency[r] = exp(log_consistency[r])
        end
        log_jac += (R - 1) * log(t.consistency_scale)
    end

    steps = zeros(Z, G_step, H)
    if H >= 2
        row_buf = Vector{Z}(undef, H)
        for g in 1:G_step
            _helmert_zero_sum!(row_buf, view(q, t.step_ranges[g]), t.step_scale)
            @inbounds for m in 1:H
                steps[g, m] = row_buf[m]
            end
        end
        log_jac += G_step * (H - 1) * log(t.step_scale)
    end

    softmin_log_kappa = pr.aggregation === :softmin ? Z(log(pr.softmin_kappa)) : zero(Z)
    softmin_kappa = Z(pr.softmin_kappa)
    if pr.softmin_kappa_mode === :estimated
        lk_z = q[only(t.softmin_kappa_z_range)]
        softmin_log_kappa = pr.softmin_log_kappa_mean + pr.softmin_log_kappa_sd * lk_z
        softmin_kappa = exp(softmin_log_kappa)
        log_jac += log(pr.softmin_log_kappa_sd) + softmin_log_kappa
    end

    return (;
        person_z,
        ability_mean,
        ability_logsd,
        ability_sd,
        cholesky_L,
        correlation_matrix,
        partial_correlations,
        log_lkj_kernel,
        person,
        log_loading,
        loading,
        standardized_loading,
        item,
        rater,
        log_consistency,
        consistency,
        steps,
        softmin_log_kappa,
        softmin_kappa,
        log_jacobian = log_jac,
    )
end

"""
Evaluate the exact normalized prior log-density on the constrained / isometric
subspace coordinates returned by `coordinates(t, q)` (before adding `c.log_jacobian`).
Satisfies `constrained_subspace_logprior(t, c) + c.log_jacobian == logprior(t, q)`
identically for all finite `q`.
"""
function constrained_subspace_logprior(t::Target, c)
    Z = eltype(c.person)
    pr = t.prior
    l2pi = log(2.0 * pi)
    lp = zero(Z)

    # 1. Standardized person coordinates z_{p, d} ~ N(0, 1)
    lp += -0.5 * (t.P * t.D) * l2pi - 0.5 * sum(abs2, c.person_z)

    # 2. Population ability mean (when :centered_items_free_mean)
    if pr.location_identification === :centered_items_free_mean
        lp += -0.5 * t.D * l2pi - t.D * log(pr.ability_mean_sd) -
            0.5 * sum(abs2, c.ability_mean) / (pr.ability_mean_sd^2)
    end

    # 3. Population ability SD sigma_{theta_d}
    if pr.ability_sd_family === :lognormal
        for d in 1:t.D
            sig = c.ability_sd[d]
            z = (log(sig) - pr.ability_logsd_mean) / pr.ability_logsd_sd
            lp += -log(sig) - log(pr.ability_logsd_sd) - 0.5 * l2pi - 0.5 * z^2
        end
    elseif pr.ability_sd_family === :half_normal
        s = pr.ability_sd_scale
        c_hn = log(2.0) - 0.5 * l2pi - log(s)
        for d in 1:t.D
            sig = c.ability_sd[d]
            lp += c_hn - 0.5 * (sig / s)^2
        end
    else # :half_t
        s = pr.ability_sd_scale
        df = pr.ability_sd_df
        c_ht = log(2.0) + SpecialFunctions.loggamma(0.5 * (df + 1.0)) -
               SpecialFunctions.loggamma(0.5 * df) - 0.5 * log(df * pi) - log(s)
        for d in 1:t.D
            sig = c.ability_sd[d]
            lp += c_ht - 0.5 * (df + 1.0) * log1p((sig * sig) / (df * s * s))
        end
    end

    # 4. Loadings
    if pr.item_slopes === :estimated_positive
        if pr.scale_identification === :geometric_mean_one
            for d in 1:t.D
                pitems = t.pure_items_by_dim[d]
                Id = length(pitems)
                if Id >= 2
                    sc = t.pure_loading_scales[d]
                    ss = sum(abs2(c.log_loading[i, d]) for i in pitems)
                    lp += -0.5 * (Id - 1) * l2pi - (Id - 1) * log(sc) - 0.5 * ss / (sc^2)
                end
            end
            for (i, d) in t.cross_loading_pairs
                a = c.loading[i, d]
                lp += -log(a) - log(pr.log_loading_sd) - 0.5 * l2pi - 0.5 * (log(a) / pr.log_loading_sd)^2
            end
        else
            for (i, d) in t.anchor_free_loading_pairs
                a = c.loading[i, d]
                lp += -log(a) - log(pr.log_loading_sd) - 0.5 * l2pi - 0.5 * (log(a) / pr.log_loading_sd)^2
            end
        end
    end

    # 5. Item difficulties
    if pr.location_identification === :zero_mean_population
        lp += -0.5 * t.I * l2pi - t.I * log(pr.item_sd) - 0.5 * sum(abs2, c.item) / (pr.item_sd^2)
    else
        for d in 1:t.D
            pitems = t.pure_items_by_dim[d]
            Id = length(pitems)
            if Id >= 2
                sc = t.pure_item_scales[d]
                ss = sum(abs2(c.item[i]) for i in pitems)
                lp += -0.5 * (Id - 1) * l2pi - (Id - 1) * log(sc) - 0.5 * ss / (sc^2)
            end
        end
        for i in t.cross_items
            lp += -0.5 * l2pi - log(pr.item_sd) - 0.5 * (c.item[i] / pr.item_sd)^2
        end
    end

    # 6. Rater severities (orthonormal zero-sum subspace)
    if t.R >= 2
        sc = t.rater_scale
        lp += -0.5 * (t.R - 1) * l2pi - (t.R - 1) * log(sc) - 0.5 * sum(abs2, c.rater) / (sc^2)
    end

    # 7. Log rater consistencies (orthonormal zero-sum subspace)
    if pr.rater_consistency === :estimated_positive && t.R >= 2
        sc = t.consistency_scale
        lp += -0.5 * (t.R - 1) * l2pi - (t.R - 1) * log(sc) - 0.5 * sum(abs2, c.log_consistency) / (sc^2)
    end

    # 8. Steps (orthonormal zero-sum subspaces)
    if t.H >= 2
        sc = t.step_scale
        G_step = t.n_step_groups
        lp += -0.5 * G_step * (t.H - 1) * l2pi - G_step * (t.H - 1) * log(sc) - 0.5 * sum(abs2, c.steps) / (sc^2)
    end

    # 9. LKJ Cholesky correlation density evaluated directly from cholesky_L (supports cross-eta reweighting)
    if pr.latent_correlation === :lkj
        lp += t.lkj_log_normalizer
        for i_d in 2:t.D
            lp += (Float64(t.D - i_d) + 2.0 * pr.lkj_eta - 2.0) * log(c.cholesky_L[i_d, i_d])
        end
    end

    # 10. Optional smooth bottleneck curvature kappa ~ LogNormal(mu_k, sd_k)
    if pr.softmin_kappa_mode === :estimated
        kap = c.softmin_kappa
        zk = (log(kap) - pr.softmin_log_kappa_mean) / pr.softmin_log_kappa_sd
        lp += -log(kap) - log(pr.softmin_log_kappa_sd) - 0.5 * l2pi - 0.5 * zk^2
    end

    return lp
end

# ---------------------------------------------------------------------------
# Exact Log-Prior, Pointwise Log-Likelihood & Analytical O(N*K) Gradient
# ---------------------------------------------------------------------------

function logprior(t::Target, q::AbstractVector{<:Real})
    _check_vector(t, q)
    Z = promote_type(Float64, eltype(q))
    pr = t.prior
    l2pi = log(2.0 * pi)
    if pr.ability_sd_family === :lognormal && pr.latent_correlation === :identity_fixed
        return -0.5 * Z(t.dimension) * l2pi - 0.5 * sum(abs2, q)
    end
    n_non_std = (pr.ability_sd_family === :lognormal ? 0 : t.D) + length(t.corr_z_range)
    n_std = t.dimension - n_non_std
    q_ss = sum(abs2, q)
    if pr.ability_sd_family !== :lognormal
        for j in t.ability_logsd_z_range
            q_ss -= abs2(q[j])
        end
    end
    for j in t.corr_z_range
        q_ss -= abs2(q[j])
    end
    lp = -0.5 * Z(n_std) * l2pi - 0.5 * q_ss

    if pr.ability_sd_family === :half_normal
        s = pr.ability_sd_scale
        c_hn = log(2.0) - 0.5 * l2pi - log(s)
        for j in t.ability_logsd_z_range
            qj = q[j]
            sig = exp(qj)
            lp += c_hn - 0.5 * (sig / s)^2 + qj
        end
    elseif pr.ability_sd_family === :half_t
        s = pr.ability_sd_scale
        df = pr.ability_sd_df
        c_ht = log(2.0) + SpecialFunctions.loggamma(0.5 * (df + 1.0)) -
               SpecialFunctions.loggamma(0.5 * df) - 0.5 * log(df * pi) - log(s)
        for j in t.ability_logsd_z_range
            qj = q[j]
            sig = exp(qj)
            lp += c_ht - 0.5 * (df + 1.0) * log1p((sig * sig) / (df * s * s)) + qj
        end
    end

    if pr.latent_correlation === :lkj
        lp += t.lkj_log_normalizer
        for (k, j) in enumerate(t.corr_z_range)
            lp += t.lkj_alphas[k] * _logsech2(q[j])
        end
    end
    return lp
end

@inline function _obs_loc_and_scale(t::Target, c, p::Int, i::Int, r::Int)
    Z = eltype(c.person)
    pr = t.prior
    s0 = pr.logit_scale
    if pr.item_slope_scope === :entire_linear_predictor
        return (c.person[p, 1] - c.item[i] - c.rater[r], s0 * c.consistency[r] * c.loading[i, 1])
    end
    adims = t.active_dims_of_item[i]
    m_act = length(adims)
    u_pi = if m_act == 1
        d1 = @inbounds adims[1]
        c.loading[i, d1] * c.person[p, d1]
    elseif pr.aggregation === :additive
        acc = zero(Z)
        @inbounds for d in adims
            acc += c.loading[i, d] * c.person[p, d]
        end
        pr.cross_loading_average ? (acc / Float64(m_act)) : acc
    else
        kap = c.softmin_kappa
        mx_s = zero(Z)
        @inbounds for (idx_d, d) in enumerate(adims)
            xd = -kap * (c.loading[i, d] * c.person[p, d])
            if idx_d == 1 || xd > mx_s
                mx_s = xd
            end
        end
        w_sum = zero(Z)
        @inbounds for d in adims
            w_sum += exp(-kap * (c.loading[i, d] * c.person[p, d]) - mx_s)
        end
        -(mx_s + log(w_sum) - log(Float64(m_act))) / kap
    end
    if pr.rater_slope_scope === :ability_only
        return (c.consistency[r] * u_pi - c.item[i] - c.rater[r], Z(s0))
    else
        return (u_pi - c.item[i] - c.rater[r], s0 * c.consistency[r])
    end
end

function pointwise_loglikelihood(t::Target, q::AbstractVector{<:Real})
    c = coordinates(t, q)
    Z = eltype(c.person)
    out = Vector{Z}(undef, t.N)
    logits = Vector{Z}(undef, t.K)

    @inbounds for n in 1:t.N
        p = t.person[n]
        i = t.item[n]
        r = t.rater[n]
        g = t.step_group_of_obs[n]
        y = t.category[n]

        loc, alpha_obs = _obs_loc_and_scale(t, c, p, i, r)

        logits[1] = zero(Z)
        mx = zero(Z)
        for k in 2:t.K
            lk = logits[k - 1] + alpha_obs * (loc - c.steps[g, k - 1])
            logits[k] = lk
            lk > mx && (mx = lk)
        end
        denom = zero(Z)
        for k in 1:t.K
            denom += exp(logits[k] - mx)
        end
        out[n] = logits[y] - (mx + log(denom))
    end
    return out
end

loglikelihood(t::Target, q::AbstractVector{<:Real}) = sum(pointwise_loglikelihood(t, q))

function L.logdensity(t::Target, q::AbstractVector)
    return loglikelihood(t, q) + logprior(t, q)
end

struct _RowAdjoints
    theta::Matrix{Float64}
    loading::Matrix{Float64}
    item::Vector{Float64}
    rater::Vector{Float64}
    consistency::Vector{Float64}
    steps::Matrix{Float64}
    logits::Vector{Float64}
    probs::Vector{Float64}
    weights::Vector{Float64}
end

mutable struct _ScaleIdGradScratch
    mu_theta::Vector{Float64}
    sigma_theta::Vector{Float64}
    u_person::Matrix{Float64}
    theta::Matrix{Float64}
    L_corr::Matrix{Float64}
    G_L::Matrix{Float64}
    log_a::Matrix{Float64}
    a_mat::Matrix{Float64}
    b_item::Vector{Float64}
    s_rater::Vector{Float64}
    log_c::Vector{Float64}
    c_rater::Vector{Float64}
    tau::Matrix{Float64}
    g_theta::Matrix{Float64}
    g_log_a::Matrix{Float64}
    g_b::Vector{Float64}
    g_s::Vector{Float64}
    g_log_c::Vector{Float64}
    g_tau::Matrix{Float64}
    logits::Vector{Float64}
    probs::Vector{Float64}
    pw_ll::Vector{Float64}
    tmp_buf::Vector{Float64}
    w_buf::Vector{Float64}
    q_buf::Vector{Float64}
    bar_shift::Vector{Float64}
    g_bar::Vector{Float64}
    g_sig_extra::Vector{Float64}
    g_log_a_extra::Matrix{Float64}
    row_chunks::Vector{_RowAdjoints}
end

function _get_scale_id_grad_scratch(t::Target)
    P, I, R, D, K, H, N, dim = t.P, t.I, t.R, t.D, t.K, t.H, t.N, t.dimension
    G_step = t.n_step_groups
    sc = get!(task_local_storage(), :_mgmfrm_scale_id_scratch) do
        _ScaleIdGradScratch(
            Float64[], Float64[], zeros(0, 0), zeros(0, 0), zeros(0, 0), zeros(0, 0),
            zeros(0, 0), zeros(0, 0),
            Float64[], Float64[], Float64[], Float64[], zeros(0, 0),
            zeros(0, 0), zeros(0, 0), Float64[], Float64[], Float64[], zeros(0, 0),
            Float64[], Float64[], Float64[], Float64[],
            Float64[], Float64[], Float64[], Float64[], Float64[], zeros(0, 0), _RowAdjoints[],
        )
    end::_ScaleIdGradScratch
    resize!(sc.mu_theta, D)
    resize!(sc.sigma_theta, D)
    size(sc.u_person) == (P, D) || (sc.u_person = Matrix{Float64}(undef, P, D))
    size(sc.theta) == (P, D) || (sc.theta = Matrix{Float64}(undef, P, D))
    if size(sc.L_corr) != (D, D)
        sc.L_corr = zeros(Float64, D, D)
        sc.G_L = zeros(Float64, D, D)
    end
    if size(sc.log_a) != (I, D)
        sc.log_a = zeros(Float64, I, D)
        sc.a_mat = zeros(Float64, I, D)
        sc.g_log_a = zeros(Float64, I, D)
        sc.g_log_a_extra = zeros(Float64, I, D)
    end
    resize!(sc.b_item, I)
    resize!(sc.s_rater, R)
    resize!(sc.log_c, R)
    resize!(sc.c_rater, R)
    if size(sc.tau) != (G_step, H)
        sc.tau = zeros(Float64, G_step, H)
        sc.g_tau = zeros(Float64, G_step, H)
    end
    size(sc.g_theta) == (P, D) || (sc.g_theta = zeros(Float64, P, D))
    resize!(sc.g_b, I)
    resize!(sc.g_s, R)
    resize!(sc.g_log_c, R)
    resize!(sc.logits, K)
    resize!(sc.probs, K)
    resize!(sc.pw_ll, N)
    resize!(sc.tmp_buf, max(I, R, G_step, H, D))
    resize!(sc.w_buf, dim)
    resize!(sc.q_buf, dim)
    resize!(sc.bar_shift, D)
    resize!(sc.g_bar, D)
    resize!(sc.g_sig_extra, D)
    return sc
end

function _eval_loadings_f64!(a_mat::Matrix{Float64}, log_a::Matrix{Float64}, tmp_buf::Vector{Float64}, t::Target, q::AbstractVector)
    pr = t.prior
    D = t.D
    fill!(log_a, 0.0)
    fill!(a_mat, 0.0)
    if pr.item_slopes === :fixed_one
        @inbounds for (i, d) in t.active_pairs
            a_mat[i, d] = 1.0
        end
        return nothing
    elseif pr.scale_identification === :geometric_mean_one
        for d in 1:D
            pitems = t.pure_items_by_dim[d]
            Id = length(pitems)
            if Id >= 2
                tmp = view(tmp_buf, 1:Id)
                _helmert_zero_sum!(tmp, view(q, t.pure_loading_ranges[d]), t.pure_loading_scales[d])
                @inbounds for (m, i) in enumerate(pitems)
                    log_a[i, d] = tmp[m]
                end
            end
        end
        @inbounds for (m, (i, d)) in enumerate(t.cross_loading_pairs)
            log_a[i, d] = pr.log_loading_sd * Float64(q[t.cross_loading_range[m]])
        end
    else
        @inbounds for (m, (i, d)) in enumerate(t.anchor_free_loading_pairs)
            log_a[i, d] = pr.log_loading_sd * Float64(q[t.anchor_free_loading_range[m]])
        end
    end
    @inbounds for (i, d) in t.active_pairs
        a_mat[i, d] = exp(log_a[i, d])
    end
    return nothing
end

_similar_row_adjoints(a) = _RowAdjoints((similar(getfield(a, f)) for f in fieldnames(_RowAdjoints))...)
_same_row_shape(a,b) = all(f -> size(getfield(a,f)) == size(getfield(b,f)), fieldnames(_RowAdjoints))

function _row_adjoints!(adj, sc, t, rows, kappa_val)
    pr = t.prior
    R, K, H = t.R, t.K, t.H
    s0 = pr.logit_scale
    theta, a_mat, b_item, s_rater, c_rater, tau = sc.theta, sc.a_mat, sc.b_item, sc.s_rater, sc.c_rater, sc.tau
    g_theta, g_log_a, g_b, g_s, g_log_c, g_tau = adj.theta, adj.loading, adj.item, adj.rater, adj.consistency, adj.steps
    logits, probs, tmp_buf, pw_ll = adj.logits, adj.probs, adj.weights, sc.pw_ll
    est_cons = pr.rater_consistency === :estimated_positive && R >= 2
    est_item_slopes = pr.item_slopes === :estimated_positive
    full_item_slope = pr.item_slope_scope === :entire_linear_predictor
    abil_only_rater = pr.rater_slope_scope === :ability_only
    use_softmin = pr.aggregation === :softmin
    use_cl_avg = pr.cross_loading_average
    est_kappa = pr.softmin_kappa_mode === :estimated
    g_log_kappa = 0.0

    @inbounds for n in rows
        p = t.person[n]
        i = t.item[n]
        r = t.rater[n]
        g = t.step_group_of_obs[n]
        y = t.category[n]
        adims = t.active_dims_of_item[i]
        m_act = length(adims)

        u_pi = 0.0
        inv_W = 0.0
        if full_item_slope
            loc = theta[p, 1] - b_item[i] - s_rater[r]
            alpha_obs = s0 * c_rater[r] * a_mat[i, 1]
        else
            if m_act == 1
                d1 = adims[1]
                u_pi = a_mat[i, d1] * theta[p, d1]
            elseif !use_softmin
                acc = 0.0
                for d in adims
                    acc += a_mat[i, d] * theta[p, d]
                end
                u_pi = use_cl_avg ? (acc / Float64(m_act)) : acc
            else
                mx_s = -kappa_val * (a_mat[i, adims[1]] * theta[p, adims[1]])
                for idx_d in 2:m_act
                    d = adims[idx_d]
                    xd = -kappa_val * (a_mat[i, d] * theta[p, d])
                    xd > mx_s && (mx_s = xd)
                end
                w_sum = 0.0
                for idx_d in 1:m_act
                    d = adims[idx_d]
                    wd = exp(-kappa_val * (a_mat[i, d] * theta[p, d]) - mx_s)
                    tmp_buf[idx_d] = wd
                    w_sum += wd
                end
                inv_W = 1.0 / w_sum
                u_pi = -(mx_s + log(w_sum) - log(Float64(m_act))) / kappa_val
            end
            if abil_only_rater
                loc = c_rater[r] * u_pi - b_item[i] - s_rater[r]
                alpha_obs = s0
            else
                loc = u_pi - b_item[i] - s_rater[r]
                alpha_obs = s0 * c_rater[r]
            end
        end

        logits[1] = 0.0
        mx = 0.0
        for k in 2:K
            lk = logits[k - 1] + alpha_obs * (loc - tau[g, k - 1])
            logits[k] = lk
            lk > mx && (mx = lk)
        end

        denom = 0.0
        for k in 1:K
            w = exp(logits[k] - mx)
            probs[k] = w
            denom += w
        end
        inv_denom = 1.0 / denom
        exp_cat = 0.0
        exp_logit = 0.0
        for k in 1:K
            pk = probs[k] * inv_denom
            probs[k] = pk
            exp_cat += Float64(k - 1) * pk
            exp_logit += pk * logits[k]
        end
        pw_ll[n] = logits[y] - (mx + log(denom))

        g_loc = alpha_obs * (Float64(y - 1) - exp_cat)
        g_b[i] -= g_loc
        g_s[r] -= g_loc
        if full_item_slope
            g_theta[p, 1] += g_loc
            if est_item_slopes
                g_log_a[i, 1] += logits[y] - exp_logit
            end
            if est_cons
                g_log_c[r] += logits[y] - exp_logit
            end
        else
            g_u = abil_only_rater ? (c_rater[r] * g_loc) : g_loc
            if est_cons
                g_log_c[r] += abil_only_rater ? (u_pi * g_u) : (logits[y] - exp_logit)
            end
            if m_act == 1
                d1 = adims[1]
                aid = a_mat[i, d1]
                g_theta[p, d1] += aid * g_u
                if est_item_slopes
                    g_log_a[i, d1] += (aid * theta[p, d1]) * g_u
                end
            elseif !use_softmin
                gu_w = use_cl_avg ? (g_u / Float64(m_act)) : g_u
                for d in adims
                    aid = a_mat[i, d]
                    g_theta[p, d] += aid * gu_w
                    if est_item_slopes
                        g_log_a[i, d] += (aid * theta[p, d]) * gu_w
                    end
                end
            else
                du_dlogk = 0.0
                for idx_d in 1:m_act
                    d = adims[idx_d]
                    aid = a_mat[i, d]
                    v_d = aid * theta[p, d]
                    pi_d = tmp_buf[idx_d] * inv_W
                    g_vd = pi_d * g_u
                    g_theta[p, d] += aid * g_vd
                    if est_item_slopes
                        g_log_a[i, d] += v_d * g_vd
                    end
                    du_dlogk += pi_d * (v_d - u_pi)
                end
                est_kappa && (g_log_kappa += du_dlogk * g_u)
            end
        end
        if H >= 2
            tail_s = 0.0
            for m in H:-1:1
                kp1 = m + 1
                tail_s += (y == kp1 ? 1.0 : 0.0) - probs[kp1]
                g_tau[g, m] -= alpha_obs * tail_s
            end
        end
    end

    return g_log_kappa
end

function L.logdensity_and_gradient(t::Target, q::AbstractVector)
    _check_vector(t, q)
    pr = t.prior
    P, I, R, D, K, H, N = t.P, t.I, t.R, t.D, t.K, t.H, t.N
    G_step = t.n_step_groups
    s0 = pr.logit_scale
    sc = _get_scale_id_grad_scratch(t)

    # 1. Forward reconstruction into pooled Float64 scratch arrays
    mu_theta = fill!(sc.mu_theta, 0.0)
    if pr.location_identification === :centered_items_free_mean
        @inbounds for d in 1:D
            mu_theta[d] = pr.ability_mean_sd * Float64(q[t.ability_mean_z_range[d]])
        end
    end

    sigma_theta = sc.sigma_theta
    if pr.ability_sd_family === :lognormal
        @inbounds for d in 1:D
            sigma_theta[d] = exp(pr.ability_logsd_mean + pr.ability_logsd_sd * Float64(q[t.ability_logsd_z_range[d]]))
        end
    else
        @inbounds for d in 1:D
            sigma_theta[d] = exp(Float64(q[t.ability_logsd_z_range[d]]))
        end
    end

    L_corr = fill!(sc.L_corr, 0.0)
    use_lkj = pr.latent_correlation === :lkj
    if use_lkj
        L_corr[1, 1] = 1.0
        k_c = 0
        for i_d in 2:D
            s_prod = 1.0
            for j_d in 1:(i_d - 1)
                k_c += 1
                qk = Float64(q[t.corr_z_range[k_c]])
                z_ij = tanh(qk)
                c_ij = exp(0.5 * _logsech2(qk))
                L_corr[i_d, j_d] = z_ij * s_prod
                s_prod *= c_ij
            end
            s_prod > 0.0 || throw(DomainError(0.0, "Cholesky diagonal underflow"))
            L_corr[i_d, i_d] = s_prod
        end
    end

    u_person = sc.u_person
    theta = sc.theta
    if use_lkj
        @inbounds for p in 1:P
            base_idx = (p - 1) * D
            for i_d in 1:D
                u_pi = 0.0
                for j_d in 1:i_d
                    u_pi += L_corr[i_d, j_d] * Float64(q[base_idx + j_d])
                end
                u_person[p, i_d] = u_pi
                theta[p, i_d] = mu_theta[i_d] + sigma_theta[i_d] * u_pi
            end
        end
    else
        idx = 0
        @inbounds for p in 1:P, d in 1:D
            idx += 1
            z_pd = Float64(q[idx])
            u_person[p, d] = z_pd
            theta[p, d] = mu_theta[d] + sigma_theta[d] * z_pd
        end
    end

    log_a = sc.log_a
    a_mat = sc.a_mat
    tmp_buf = sc.tmp_buf
    _eval_loadings_f64!(a_mat, log_a, tmp_buf, t, q)

    b_item = fill!(sc.b_item, 0.0)
    if pr.location_identification === :zero_mean_population
        @inbounds for i in 1:I
            b_item[i] = pr.item_sd * Float64(q[t.item_free_range[i]])
        end
    else
        for d in 1:D
            pitems = t.pure_items_by_dim[d]
            Id = length(pitems)
            if Id >= 2
                tmp = view(tmp_buf, 1:Id)
                _helmert_zero_sum!(tmp, view(q, t.pure_item_ranges[d]), t.pure_item_scales[d])
                @inbounds for (m, i) in enumerate(pitems)
                    b_item[i] = tmp[m]
                end
            end
        end
        @inbounds for (m, i) in enumerate(t.cross_items)
            b_item[i] = pr.item_sd * Float64(q[t.cross_item_range[m]])
        end
    end

    s_rater = fill!(sc.s_rater, 0.0)
    R >= 2 && _helmert_zero_sum!(s_rater, view(q, t.rater_range), t.rater_scale)

    log_c = fill!(sc.log_c, 0.0)
    c_rater = fill!(sc.c_rater, 1.0)
    if pr.rater_consistency === :estimated_positive && R >= 2
        _helmert_zero_sum!(log_c, view(q, t.consistency_range), t.consistency_scale)
        @inbounds for r in 1:R
            c_rater[r] = exp(log_c[r])
        end
    end

    tau = sc.tau
    if H == 1
        fill!(tau, 0.0)
    elseif H >= 2
        row_buf = view(tmp_buf, 1:H)
        for g in 1:G_step
            _helmert_zero_sum!(row_buf, view(q, t.step_ranges[g]), t.step_scale)
            @inbounds for m in 1:H
                tau[g, m] = row_buf[m]
            end
        end
    end

    # 2. Likelihood evaluation + adjoint accumulation in O(N * K)
    g_theta = fill!(sc.g_theta, 0.0)
    g_log_a = fill!(sc.g_log_a, 0.0)
    g_b = fill!(sc.g_b, 0.0)
    g_s = fill!(sc.g_s, 0.0)
    g_log_c = fill!(sc.g_log_c, 0.0)
    g_tau = fill!(sc.g_tau, 0.0)

    adj = _RowAdjoints(g_theta, g_log_a, g_b, g_s, g_log_c, g_tau, sc.logits, sc.probs, sc.tmp_buf)
    est_kappa = pr.softmin_kappa_mode === :estimated
    kappa_val = est_kappa ?
        exp(pr.softmin_log_kappa_mean + pr.softmin_log_kappa_sd * Float64(q[only(t.softmin_kappa_z_range)])) :
        pr.softmin_kappa
    pw_ll = sc.pw_ll
    if N < 8000
        g_log_kappa = _row_adjoints!(adj, sc, t, 1:N, kappa_val)
    else
        # Keep both partitions and merge order independent of the thread count.
        chunks = min(8, cld(N, 2048))
        if length(sc.row_chunks) != chunks || !_same_row_shape(sc.row_chunks[1],adj)
            sc.row_chunks = [_similar_row_adjoints(adj) for _ in 1:chunks]
        end
        kappa_parts = zeros(chunks)
        B._parallel_ranges(chunks, N) do indices
            for c in indices
                rows = (fld((c-1)*N,chunks)+1):fld(c*N,chunks)
                local_adj = sc.row_chunks[c]
                for field in (:theta,:loading,:item,:rater,:consistency,:steps)
                    fill!(getfield(local_adj,field),0.0)
                end
                kappa_parts[c] = _row_adjoints!(local_adj, sc, t, rows, kappa_val)
            end
        end
        for local_adj in sc.row_chunks, field in (:theta,:loading,:item,:rater,:consistency,:steps)
            getfield(adj,field) .+= getfield(local_adj,field)
        end
        g_log_kappa = sum(kappa_parts)
    end

    est_item_slopes = pr.item_slopes === :estimated_positive
    est_cons = pr.rater_consistency === :estimated_positive && R >= 2
    # 3. Pullback into unconstrained coordinates q + exact prior + Jacobian gradients
    grad = Vector{Float64}(undef, t.dimension)

    if use_lkj
        G_L = fill!(sc.G_L, 0.0)
        @inbounds for p in 1:P
            base_idx = (p - 1) * D
            for j_d in 1:D
                acc_z = 0.0
                z_pj = Float64(q[base_idx + j_d])
                for i_d in j_d:D
                    g_u = sigma_theta[i_d] * g_theta[p, i_d]
                    acc_z += L_corr[i_d, j_d] * g_u
                    G_L[i_d, j_d] += g_u * z_pj
                end
                grad[base_idx + j_d] = acc_z - z_pj
            end
        end

        k_offset = 0
        for i_d in 2:D
            n_row = i_d - 1
            # Reconstruct row prefix products s_{i, 0:(n_row-1)} for reverse-mode pullback
            s_pref = view(tmp_buf, 1:n_row)
            s_cur = 1.0
            for j_d in 1:n_row
                s_pref[j_d] = s_cur
                s_cur *= exp(0.5 * _logsech2(Float64(q[t.corr_z_range[k_offset + j_d]])))
            end
            s_bar = G_L[i_d, i_d]
            for j_d in n_row:-1:1
                k_c = k_offset + j_d
                q_idx = t.corr_z_range[k_c]
                z_ij = tanh(Float64(q[q_idx]))
                c_ij = exp(0.5 * _logsech2(Float64(q[q_idx])))
                sp = s_pref[j_d]
                g_ij = G_L[i_d, j_d]
                grad[q_idx] = c_ij * sp * (g_ij * c_ij - s_bar * z_ij) - 2.0 * t.lkj_alphas[k_c] * z_ij
                s_bar = s_bar * c_ij + g_ij * z_ij
            end
            k_offset += n_row
        end
    else
        idx = 0
        @inbounds for p in 1:P, d in 1:D
            idx += 1
            qj = Float64(q[idx])
            grad[idx] = sigma_theta[d] * g_theta[p, d] - qj
        end
    end

    if pr.location_identification === :centered_items_free_mean
        @inbounds for d in 1:D
            sum_gth = 0.0
            for p in 1:P
                sum_gth += g_theta[p, d]
            end
            j = t.ability_mean_z_range[d]
            grad[j] = pr.ability_mean_sd * sum_gth - Float64(q[j])
        end
    end

    @inbounds for d in 1:D
        dot_u = 0.0
        for p in 1:P
            dot_u += g_theta[p, d] * u_person[p, d]
        end
        j = t.ability_logsd_z_range[d]
        sig = sigma_theta[d]
        if pr.ability_sd_family === :lognormal
            grad[j] = (pr.ability_logsd_sd * sig) * dot_u - Float64(q[j])
        elseif pr.ability_sd_family === :half_normal
            s = pr.ability_sd_scale
            grad[j] = sig * dot_u + (1.0 - (sig / s)^2)
        else # :half_t
            s = pr.ability_sd_scale
            df = pr.ability_sd_df
            sig2 = sig * sig
            grad[j] = sig * dot_u + (1.0 - (df + 1.0) * sig2 / (df * s * s + sig2))
        end
    end

    if est_item_slopes
        if pr.scale_identification === :geometric_mean_one
            for d in 1:D
                pitems = t.pure_items_by_dim[d]
                Id = length(pitems)
                if Id >= 2
                    g_sub = view(tmp_buf, 1:Id)
                    @inbounds for (m, i) in enumerate(pitems)
                        g_sub[m] = g_log_a[i, d]
                    end
                    rng_d = t.pure_loading_ranges[d]
                    _helmert_zero_sum_pullback!(view(grad, rng_d), view(q, rng_d), g_sub, t.pure_loading_scales[d])
                end
            end
            @inbounds for (m, (i, d)) in enumerate(t.cross_loading_pairs)
                j = t.cross_loading_range[m]
                grad[j] = pr.log_loading_sd * g_log_a[i, d] - Float64(q[j])
            end
        else
            @inbounds for (m, (i, d)) in enumerate(t.anchor_free_loading_pairs)
                j = t.anchor_free_loading_range[m]
                grad[j] = pr.log_loading_sd * g_log_a[i, d] - Float64(q[j])
            end
        end
    end

    if pr.location_identification === :zero_mean_population
        @inbounds for i in 1:I
            j = t.item_free_range[i]
            grad[j] = pr.item_sd * g_b[i] - Float64(q[j])
        end
    else
        for d in 1:D
            pitems = t.pure_items_by_dim[d]
            Id = length(pitems)
            if Id >= 2
                g_sub = view(tmp_buf, 1:Id)
                @inbounds for (m, i) in enumerate(pitems)
                    g_sub[m] = g_b[i]
                end
                rng_d = t.pure_item_ranges[d]
                _helmert_zero_sum_pullback!(view(grad, rng_d), view(q, rng_d), g_sub, t.pure_item_scales[d])
            end
        end
        @inbounds for (m, i) in enumerate(t.cross_items)
            j = t.cross_item_range[m]
            grad[j] = pr.item_sd * g_b[i] - Float64(q[j])
        end
    end

    if R >= 2
        _helmert_zero_sum_pullback!(view(grad, t.rater_range), view(q, t.rater_range), g_s, t.rater_scale)
    end
    if est_cons
        _helmert_zero_sum_pullback!(view(grad, t.consistency_range), view(q, t.consistency_range), g_log_c, t.consistency_scale)
    end
    if H >= 2
        g_row = view(tmp_buf, 1:H)
        for g in 1:G_step
            @inbounds for m in 1:H
                g_row[m] = g_tau[g, m]
            end
            rng_g = t.step_ranges[g]
            _helmert_zero_sum_pullback!(view(grad, rng_g), view(q, rng_g), g_row, t.step_scale)
        end
    end
    if est_kappa
        jk = only(t.softmin_kappa_z_range)
        grad[jk] = pr.softmin_log_kappa_sd * g_log_kappa - Float64(q[jk])
    end

    total_ll = sum(pw_ll)
    lp_prior = logprior(t, q)
    lp = total_ll + lp_prior
    (isfinite(lp) && all(isfinite, grad)) ||
        throw(DomainError(lp, "non-finite logposterior or gradient in ScaleIdentifiedMGMFRM"))
    return (lp, grad)
end

# ---------------------------------------------------------------------------
# Matching Stan Code & Data Dictionary (CmdStan 2.39.0 Parity & StanAdapter)
# ---------------------------------------------------------------------------

const STAN_CODE = """
functions {
  vector helmert_zero_sum(vector v) {
    int m = num_elements(v);
    vector[m + 1] out;
    real tail = 0.0;
    for (idx in 1:m) {
      int j = m - idx + 1;
      real val = v[j] / sqrt(1.0 * j * (j + 1));
      out[j + 1] = tail - j * val;
      tail += val;
    }
    out[1] = tail;
    return out;
  }
}
data {
  int<lower=1> N;
  int<lower=1> P;
  int<lower=1> I;
  int<lower=1> R;
  int<lower=1> D;
  int<lower=2> K;
  int<lower=1> G_step;
  int<lower=1> D_raw;
  int<lower=1, upper=2> scale_mode;
  int<lower=1, upper=2> location_mode;
  int<lower=0, upper=1> est_item_slopes;
  int<lower=1, upper=2> item_slope_scope_mode;
  int<lower=1, upper=2> rater_slope_scope_mode;
  int<lower=1, upper=2> aggregation_mode;
  int<lower=0, upper=1> cross_loading_avg_mode;
  int<lower=0, upper=2> softmin_kappa_mode;
  real<lower=0> softmin_kappa_fixed;
  real softmin_log_kappa_mean;
  real<lower=0> softmin_log_kappa_sd;
  int<lower=0, upper=1> est_consistency;
  int<lower=1, upper=3> sd_mode;
  real<lower=0> ability_sd_scale;
  real<lower=0> ability_sd_df;
  int<lower=0, upper=1> corr_mode;
  real<lower=0> lkj_eta;
  real<lower=0> logit_scale;
  real ability_logsd_mean;
  real<lower=0> ability_logsd_sd;
  real<lower=0> ability_mean_sd;
  real<lower=0> log_loading_sd;
  real<lower=0> item_sd;
  real<lower=0> rater_sd;
  real<lower=0> log_consistency_sd;
  real<lower=0> step_sd;
  array[N] int<lower=1, upper=P> person;
  array[N] int<lower=1, upper=I> item;
  array[N] int<lower=1, upper=R> rater;
  array[N] int<lower=1, upper=G_step> step_group;
  array[N] int<lower=1, upper=K> y;
  int<lower=I> total_active_pairs;
  array[I] int<lower=1, upper=D> item_active_count;
  array[I] int<lower=0, upper=total_active_pairs> item_active_offset;
  array[total_active_pairs] int<lower=1, upper=D> item_active_dims;
  int<lower=D> total_pure_items;
  array[D] int<lower=1, upper=I> pure_count;
  array[D] int<lower=0, upper=I> pure_offset;
  array[total_pure_items] int<lower=1, upper=I> pure_items;
  int<lower=0> n_cross_items;
  array[n_cross_items] int<lower=1, upper=I> cross_items;
  int<lower=0> n_cross_loadings;
  array[n_cross_loadings] int<lower=1, upper=I> cross_loading_item;
  array[n_cross_loadings] int<lower=1, upper=D> cross_loading_dim;
  array[D] int<lower=0, upper=I> anchor_item;
  int<lower=0> n_anchor_free_loadings;
  array[n_anchor_free_loadings] int<lower=1, upper=I> anchor_free_item;
  array[n_anchor_free_loadings] int<lower=1, upper=D> anchor_free_dim;
}
parameters {
  vector[D_raw] q;
}
model {
  int H = K - 1;
  int cursor = 0;
  int n_non_std = (sd_mode == 1 ? 0 : D) + (corr_mode == 1 ? (D * (D - 1)) %/% 2 : 0);
  int n_std = D_raw - n_non_std;
  real non_std_ss = 0.0;
  matrix[P, D] z_theta;
  vector[D] mu_theta = rep_vector(0.0, D);
  vector[D] sigma_theta;
  matrix[P, D] theta;
  matrix[I, D] a_mat = rep_matrix(0.0, I, D);
  vector[I] b_item = rep_vector(0.0, I);
  vector[R] s_rater = rep_vector(0.0, R);
  vector[R] c_rater = rep_vector(1.0, R);
  matrix[G_step, H] tau = rep_matrix(0.0, G_step, H);

  for (p in 1:P) {
    for (d in 1:D) {
      cursor += 1;
      z_theta[p, d] = q[cursor];
    }
  }
  if (location_mode == 2) {
    for (d in 1:D) {
      cursor += 1;
      mu_theta[d] = ability_mean_sd * q[cursor];
    }
  }
  for (d in 1:D) {
    cursor += 1;
    if (sd_mode == 1) {
      sigma_theta[d] = exp(ability_logsd_mean + ability_logsd_sd * q[cursor]);
    } else if (sd_mode == 2) {
      real qd = q[cursor];
      non_std_ss += qd * qd;
      sigma_theta[d] = exp(qd);
      target += log(2.0) + normal_lpdf(sigma_theta[d] | 0.0, ability_sd_scale) + qd;
    } else {
      real qd = q[cursor];
      non_std_ss += qd * qd;
      sigma_theta[d] = exp(qd);
      target += log(2.0) + student_t_lpdf(sigma_theta[d] | ability_sd_df, 0.0, ability_sd_scale) + qd;
    }
  }

  if (est_item_slopes == 0) {
    for (d in 1:D) {
      int Id = pure_count[d];
      int off = pure_offset[d];
      for (m in 1:Id) {
        a_mat[pure_items[off + m], d] = 1.0;
      }
    }
  } else if (scale_mode == 1) {
    for (d in 1:D) {
      int Id = pure_count[d];
      int off = pure_offset[d];
      if (Id == 1) {
        a_mat[pure_items[off + 1], d] = 1.0;
      } else {
        real sc = log_loading_sd * sqrt((1.0 * Id) / (Id - 1.0));
        vector[Id] la = sc * helmert_zero_sum(segment(q, cursor + 1, Id - 1));
        cursor += Id - 1;
        for (m in 1:Id) {
          a_mat[pure_items[off + m], d] = exp(la[m]);
        }
      }
    }
    for (m in 1:n_cross_loadings) {
      cursor += 1;
      a_mat[cross_loading_item[m], cross_loading_dim[m]] = exp(log_loading_sd * q[cursor]);
    }
  } else {
    for (d in 1:D) {
      a_mat[anchor_item[d], d] = 1.0;
    }
    for (m in 1:n_anchor_free_loadings) {
      cursor += 1;
      a_mat[anchor_free_item[m], anchor_free_dim[m]] = exp(log_loading_sd * q[cursor]);
    }
  }

  if (location_mode == 1) {
    for (i in 1:I) {
      cursor += 1;
      b_item[i] = item_sd * q[cursor];
    }
  } else {
    for (d in 1:D) {
      int Id = pure_count[d];
      int off = pure_offset[d];
      if (Id >= 2) {
        real sc = item_sd * sqrt((1.0 * Id) / (Id - 1.0));
        vector[Id] bv = sc * helmert_zero_sum(segment(q, cursor + 1, Id - 1));
        cursor += Id - 1;
        for (m in 1:Id) {
          b_item[pure_items[off + m]] = bv[m];
        }
      }
    }
    for (m in 1:n_cross_items) {
      cursor += 1;
      b_item[cross_items[m]] = item_sd * q[cursor];
    }
  }

  if (R >= 2) {
    real sc = rater_sd * sqrt((1.0 * R) / (R - 1.0));
    s_rater = sc * helmert_zero_sum(segment(q, cursor + 1, R - 1));
    cursor += R - 1;
  }
  if (est_consistency == 1 && R >= 2) {
    real sc = log_consistency_sd * sqrt((1.0 * R) / (R - 1.0));
    c_rater = exp(sc * helmert_zero_sum(segment(q, cursor + 1, R - 1)));
    cursor += R - 1;
  }
  if (H >= 2) {
    real sc = step_sd * sqrt((1.0 * H) / (H - 1.0));
    for (g in 1:G_step) {
      row_vector[H] r_tau = to_row_vector(sc * helmert_zero_sum(segment(q, cursor + 1, H - 1)));
      cursor += H - 1;
      tau[g] = r_tau;
    }
  }

  if (corr_mode == 1) {
    matrix[D, D] L_corr = rep_matrix(0.0, D, D);
    L_corr[1, 1] = 1.0;
    for (i_d in 2:D) {
      real log_rem = 0.0;
      for (j_d in 1:(i_d - 1)) {
        cursor += 1;
        real qk = q[cursor];
        non_std_ss += qk * qk;
        real z_ij = tanh(qk);
        real log_delta = 2 * (log(2.0) - abs(qk) - log1p_exp(-2 * abs(qk)));
        L_corr[i_d, j_d] = z_ij * exp(0.5 * log_rem);
        target += log_delta + 0.5 * log_rem;
        log_rem += log_delta;
      }
      L_corr[i_d, i_d] = exp(0.5 * log_rem);
    }
    target += lkj_corr_cholesky_lpdf(L_corr | lkj_eta);
    for (p in 1:P) {
      vector[D] u_p = L_corr * to_vector(z_theta[p]);
      for (d in 1:D) {
        theta[p, d] = mu_theta[d] + sigma_theta[d] * u_p[d];
      }
    }
  } else {
    for (p in 1:P) {
      for (d in 1:D) {
        theta[p, d] = mu_theta[d] + sigma_theta[d] * z_theta[p, d];
      }
    }
  }
  real kappa_val = softmin_kappa_fixed;
  if (softmin_kappa_mode == 2) {
    cursor += 1;
    kappa_val = exp(softmin_log_kappa_mean + softmin_log_kappa_sd * q[cursor]);
  }

  target += -0.5 * n_std * log(2.0 * pi()) - 0.5 * (dot_self(q) - non_std_ss);

  for (n in 1:N) {
    int p = person[n];
    int i = item[n];
    int r = rater[n];
    int g = step_group[n];
    real loc;
    real alpha_obs;
    if (item_slope_scope_mode == 2) {
      loc = theta[p, 1] - b_item[i] - s_rater[r];
      alpha_obs = logit_scale * c_rater[r] * a_mat[i, 1];
    } else {
      int m_act = item_active_count[i];
      int a_off = item_active_offset[i];
      real u_pi;
      if (m_act == 1) {
        int d1 = item_active_dims[a_off + 1];
        u_pi = a_mat[i, d1] * theta[p, d1];
      } else if (aggregation_mode == 1) {
        real acc = 0.0;
        for (m in 1:m_act) {
          int d = item_active_dims[a_off + m];
          acc += a_mat[i, d] * theta[p, d];
        }
        u_pi = cross_loading_avg_mode == 1 ? (acc / m_act) : acc;
      } else {
        vector[m_act] neg_scaled;
        for (m in 1:m_act) {
          int d = item_active_dims[a_off + m];
          neg_scaled[m] = -kappa_val * (a_mat[i, d] * theta[p, d]);
        }
        u_pi = -(log_sum_exp(neg_scaled) - log(1.0 * m_act)) / kappa_val;
      }
      if (rater_slope_scope_mode == 2) {
        loc = c_rater[r] * u_pi - b_item[i] - s_rater[r];
        alpha_obs = logit_scale;
      } else {
        loc = u_pi - b_item[i] - s_rater[r];
        alpha_obs = logit_scale * c_rater[r];
      }
    }
    vector[K] logits;
    logits[1] = 0.0;
    for (k in 2:K) {
      logits[k] = logits[k - 1] + alpha_obs * (loc - tau[g, k - 1]);
    }
    target += logits[y[n]] - log_sum_exp(logits);
  }
}
"""

stan_code() = STAN_CODE
stan_code(::Target) = STAN_CODE

function stan_data(t::Target)
    pr = t.prior
    pure_counts = Int[length(t.pure_items_by_dim[d]) for d in 1:t.D]
    pure_offsets = zeros(Int, t.D)
    for d in 2:t.D
        pure_offsets[d] = pure_offsets[d - 1] + pure_counts[d - 1]
    end
    pure_flat = reduce(vcat, t.pure_items_by_dim; init = Int[])
    act_counts = Int[length(t.active_dims_of_item[i]) for i in 1:t.I]
    act_offsets = zeros(Int, t.I)
    for i in 2:t.I
        act_offsets[i] = act_offsets[i - 1] + act_counts[i - 1]
    end
    act_flat = reduce(vcat, t.active_dims_of_item; init = Int[])
    anc_vec = pr.scale_identification === :anchor_item ? copy(t.anchor_item_indices) : zeros(Int, t.D)
    sd_mode = pr.ability_sd_family === :lognormal ? 1 : (pr.ability_sd_family === :half_normal ? 2 : 3)
    sk_mode_int = pr.softmin_kappa_mode === :none ? 0 : (pr.softmin_kappa_mode === :fixed ? 1 : 2)

    return Dict{String, Any}(
        "N" => t.N,
        "P" => t.P,
        "I" => t.I,
        "R" => t.R,
        "D" => t.D,
        "K" => t.K,
        "G_step" => t.n_step_groups,
        "D_raw" => t.dimension,
        "scale_mode" => pr.scale_identification === :geometric_mean_one ? 1 : 2,
        "location_mode" => pr.location_identification === :zero_mean_population ? 1 : 2,
        "est_item_slopes" => pr.item_slopes === :estimated_positive ? 1 : 0,
        "item_slope_scope_mode" => pr.item_slope_scope === :entire_linear_predictor ? 2 : 1,
        "rater_slope_scope_mode" => pr.rater_slope_scope === :ability_only ? 2 : 1,
        "aggregation_mode" => pr.aggregation === :softmin ? 2 : 1,
        "cross_loading_avg_mode" => pr.cross_loading_average ? 1 : 0,
        "softmin_kappa_mode" => sk_mode_int,
        "softmin_kappa_fixed" => pr.softmin_kappa,
        "softmin_log_kappa_mean" => pr.softmin_log_kappa_mean,
        "softmin_log_kappa_sd" => pr.softmin_log_kappa_sd,
        "est_consistency" => pr.rater_consistency === :estimated_positive ? 1 : 0,
        "sd_mode" => sd_mode,
        "ability_sd_scale" => pr.ability_sd_scale,
        "ability_sd_df" => isfinite(pr.ability_sd_df) ? pr.ability_sd_df : 4.0,
        "corr_mode" => pr.latent_correlation === :lkj ? 1 : 0,
        "lkj_eta" => pr.lkj_eta,
        "logit_scale" => pr.logit_scale,
        "ability_logsd_mean" => pr.ability_logsd_mean,
        "ability_logsd_sd" => pr.ability_logsd_sd,
        "ability_mean_sd" => pr.ability_mean_sd,
        "log_loading_sd" => pr.log_loading_sd,
        "item_sd" => pr.item_sd,
        "rater_sd" => pr.rater_sd,
        "log_consistency_sd" => pr.log_consistency_sd,
        "step_sd" => pr.step_sd,
        "person" => copy(t.person),
        "item" => copy(t.item),
        "rater" => copy(t.rater),
        "step_group" => copy(t.step_group_of_obs),
        "y" => copy(t.category),
        "total_active_pairs" => length(act_flat),
        "item_active_count" => act_counts,
        "item_active_offset" => act_offsets,
        "item_active_dims" => act_flat,
        "total_pure_items" => length(pure_flat),
        "pure_count" => pure_counts,
        "pure_offset" => pure_offsets,
        "pure_items" => pure_flat,
        "n_cross_items" => length(t.cross_items),
        "cross_items" => copy(t.cross_items),
        "n_cross_loadings" => length(t.cross_loading_pairs),
        "cross_loading_item" => Int[first(x) for x in t.cross_loading_pairs],
        "cross_loading_dim" => Int[last(x) for x in t.cross_loading_pairs],
        "anchor_item" => anc_vec,
        "n_anchor_free_loadings" => length(t.anchor_free_loading_pairs),
        "anchor_free_item" => Int[first(x) for x in t.anchor_free_loading_pairs],
        "anchor_free_dim" => Int[last(x) for x in t.anchor_free_loading_pairs],
    )
end

# ---------------------------------------------------------------------------
# Contract, Design Summary, Prior Draws & Simulation
# ---------------------------------------------------------------------------

function _helmert_basis_matrix(L::Int)
    L <= 1 && return zeros(Float64, L, 0)
    H = zeros(Float64, L, L - 1)
    for k in 1:(L - 1)
        denom = sqrt(Float64(k) * Float64(k + 1))
        for j in 1:k
            H[j, k] = 1.0 / denom
        end
        H[k + 1, k] = -Float64(k) / denom
    end
    return H
end

function q_structure_summary(t::Target)
    obs_pd = zeros(Int, t.P, t.D)
    pure_obs_pd = zeros(Int, t.P, t.D)
    pure_sets = [Set(t.pure_items_by_dim[d]) for d in 1:t.D]
    for n in 1:t.N
        p_n = t.person[n]
        i_n = t.item[n]
        ad = t.active_dims_of_item[i_n]
        for d in ad
            obs_pd[p_n, d] += 1
            (length(ad) == 1 && (i_n in pure_sets[d])) && (pure_obs_pd[p_n, d] += 1)
        end
    end
    coobs = zeros(Int, t.D, t.D)
    pure_coobs = zeros(Int, t.D, t.D)
    for d1 in 1:t.D, d2 in 1:t.D
        cnt = 0
        pcnt = 0
        for p in 1:t.P
            (obs_pd[p, d1] > 0 && obs_pd[p, d2] > 0) && (cnt += 1)
            (pure_obs_pd[p, d1] > 0 && pure_obs_pd[p, d2] > 0) && (pcnt += 1)
        end
        coobs[d1, d2] = cnt
        pure_coobs[d1, d2] = pcnt
    end
    cross_bridges = NamedTuple[
        let ad = t.active_dims_of_item[i],
            p_on_i = unique(t.person[n] for n in 1:t.N if t.item[n] == i),
            n_anchored = count(p -> all(d -> pure_obs_pd[p, d] > 0, ad), p_on_i)
            (;
                item = t.item_levels[i],
                active_dimensions = Tuple(ad),
                n_persons_observed = length(p_on_i),
                n_persons_with_pure_anchors_on_all_active_dims = n_anchored,
            )
        end for i in t.cross_items
    ]
    cls = isempty(t.cross_items) ? (t.D == 1 ? :unidimensional : :between_item) : :mixed_between_and_within_item
    min_pure_coobs = t.D >= 2 ? minimum(pure_coobs[d1, d2] for d1 in 1:t.D for d2 in (d1 + 1):t.D) : count(>(0), view(pure_obs_pd, :, 1))
    comp_sep = t.D >= 2 && !isempty(t.cross_items) && any(r -> r.n_persons_with_pure_anchors_on_all_active_dims >= 2, cross_bridges)
    return (;
        classification = cls,
        dimensions = t.D,
        dimension_labels = copy(t.dimension_labels),
        pure_items_per_dimension = Tuple(length(v) for v in t.pure_items_by_dim),
        n_cross_loaded_items = length(t.cross_items),
        cross_loaded_items = [t.item_levels[i] for i in t.cross_items],
        person_dimension_coobservation = coobs,
        person_pure_item_coobservation = pure_coobs,
        min_pairwise_pure_coobservation = min_pure_coobs,
        cross_item_person_bridges = cross_bridges,
        compensation_separable_algebraically = comp_sep,
        compensation_high_correlation_caveat = t.D >= 2 && !isempty(t.cross_items) ?
            :indistinguishable_when_latent_correlation_exceeds_approx_0_80 : :not_applicable,
    )
end

function design_matrices(t::Target)
    pr = t.prior
    s0 = pr.logit_scale
    P, I, R, D, K, H = t.P, t.I, t.R, t.D, t.K, t.H
    G_step = t.n_step_groups

    pat_lookup = Dict{Tuple{Int, Int, Int}, Int}()
    pat_triples = Tuple{Int, Int, Int}[]
    pat_counts = Int[]
    pattern_of_row = Vector{Int}(undef, t.N)
    for n in 1:t.N
        key = (t.item[n], t.rater[n], t.step_group_of_obs[n])
        u = get(pat_lookup, key, 0)
        if u == 0
            push!(pat_triples, key)
            push!(pat_counts, 1)
            u = length(pat_triples)
            pat_lookup[key] = u
        else
            pat_counts[u] += 1
        end
        pattern_of_row[n] = u
    end
    U = length(pat_triples)
    M_tot = U * K
    pattern_ranges = [((u - 1) * K + 1):(u * K) for u in 1:U]
    pattern_table = [
        let (i, r, g) = pat_triples[u]
            (;
                pattern = u,
                item = t.item_levels[i],
                rater = t.rater_levels[r],
                step_group = t.step_owner === :global ? :global : t.step_group_levels[g],
                active_dimensions = copy(t.active_dims_of_item[i]),
                n_observations = pat_counts[u],
            )
        end for u in 1:U
    ]

    loc_model_names = String[]
    fixed_loc_names = Set{String}()
    for d in 1:D
        nm = "ability_mean[dim=$d]"
        push!(loc_model_names, nm)
        pr.location_identification === :zero_mean_population && push!(fixed_loc_names, nm)
    end
    for i in 1:I
        nm = "item[$(_fmt_label(t.item_levels[i]))]"
        push!(loc_model_names, nm)
        nm in t.fixed_model_names && push!(fixed_loc_names, nm)
    end
    for r in 1:R
        nm = "rater[$(_fmt_label(t.rater_levels[r]))]"
        push!(loc_model_names, nm)
        nm in t.fixed_model_names && push!(fixed_loc_names, nm)
    end
    for g in 1:G_step, m in 1:H
        g_lbl = t.step_owner === :global ? "global" : _fmt_label(t.step_group_levels[g])
        nm = "step[$g_lbl, $m]"
        push!(loc_model_names, nm)
        nm in t.fixed_model_names && push!(fixed_loc_names, nm)
    end
    n_loc_model = length(loc_model_names)
    xi0_model = zeros(Float64, n_loc_model)

    rows_A = Int[]
    cols_A = Int[]
    vals_A = Float64[]
    B_pattern = zeros(Float64, M_tot)
    B_dim = zeros(Float64, M_tot, D)
    offset_pattern = zeros(Float64, M_tot)

    for u in 1:U
        (i, r, g) = pat_triples[u]
        ad = t.active_dims_of_item[i]
        w_i = pr.cross_loading_average ? inv(Float64(length(ad))) : 1.0
        for lk in 1:K
            slot = (u - 1) * K + lk
            k0 = lk - 1
            B_pattern[slot] = Float64(k0) * s0
            for d in ad
                B_dim[slot, d] = Float64(k0) * s0 * w_i
            end
            k0 == 0 && continue
            for d in ad
                push!(rows_A, slot); push!(cols_A, d); push!(vals_A, Float64(k0) * s0 * w_i)
            end
            push!(rows_A, slot); push!(cols_A, D + i); push!(vals_A, -Float64(k0) * s0)
            push!(rows_A, slot); push!(cols_A, D + I + r); push!(vals_A, -Float64(k0) * s0)
            for m in 1:k0
                push!(rows_A, slot); push!(cols_A, D + I + R + (g - 1) * H + m); push!(vals_A, -s0)
            end
        end
    end
    A_model = sparse(rows_A, cols_A, vals_A, M_tot, n_loc_model)

    rows_J = Int[]
    cols_J = Int[]
    vals_J = Float64[]
    loc_free_names = String[]
    col_cur = 0
    if pr.location_identification === :centered_items_free_mean
        for d in 1:D
            col_cur += 1
            push!(rows_J, d); push!(cols_J, col_cur); push!(vals_J, 1.0)
            push!(loc_free_names, "ability_mean_z[dim=$d]")
        end
        for d in 1:D
            pitems = t.pure_items_by_dim[d]
            Id = length(pitems)
            if Id >= 2
                Hd = _helmert_basis_matrix(Id)
                for k in 1:(Id - 1)
                    col_cur += 1
                    push!(loc_free_names, "item_contrast[dim=$d, k=$k]")
                    for (m, i) in enumerate(pitems)
                        v = Hd[m, k]
                        v == 0.0 || (push!(rows_J, D + i); push!(cols_J, col_cur); push!(vals_J, v))
                    end
                end
            end
        end
        for i in t.cross_items
            col_cur += 1
            push!(rows_J, D + i); push!(cols_J, col_cur); push!(vals_J, 1.0)
            push!(loc_free_names, "item_z[$(_fmt_label(t.item_levels[i]))]")
        end
    else
        for i in 1:I
            col_cur += 1
            push!(rows_J, D + i); push!(cols_J, col_cur); push!(vals_J, 1.0)
            push!(loc_free_names, "item_z[$(_fmt_label(t.item_levels[i]))]")
        end
    end
    if R >= 2
        Hr = _helmert_basis_matrix(R)
        for k in 1:(R - 1)
            col_cur += 1
            push!(loc_free_names, "rater_contrast[k=$k]")
            for r in 1:R
                v = Hr[r, k]
                v == 0.0 || (push!(rows_J, D + I + r); push!(cols_J, col_cur); push!(vals_J, v))
            end
        end
    end
    if H >= 2
        Hh = _helmert_basis_matrix(H)
        for g in 1:G_step
            g_lbl = t.step_owner === :global ? "global" : _fmt_label(t.step_group_levels[g])
            for k in 1:(H - 1)
                col_cur += 1
                push!(loc_free_names, "step_contrast[$g_lbl, k=$k]")
                for m in 1:H
                    v = Hh[m, k]
                    v == 0.0 || (push!(rows_J, D + I + R + (g - 1) * H + m); push!(cols_J, col_cur); push!(vals_J, v))
                end
            end
        end
    end
    J_model = sparse(rows_J, cols_J, vals_J, n_loc_model, col_cur)
    A_pattern = A_model * J_model
    dropzeros!(A_pattern)
    loc_rank = B.AdditiveFacets._mrcml_spqr_rank(A_pattern, loc_free_names)

    return (;
        A_pattern,
        A_model,
        B_pattern,
        B_dimension_pattern = B_dim,
        offset_pattern,
        base_offset_pattern = copy(offset_pattern),
        xi0_model,
        J_model,
        Q = copy(t.q_matrix),
        pattern_of_row,
        pattern_ranges,
        pattern_table,
        free_names = loc_free_names,
        model_names = loc_model_names,
        fixed_model_names = sort!(collect(fixed_loc_names)),
        location_mode = pr.location_identification,
        intercept_slope_invariant = (pr.item_slope_scope === :ability_only && pr.rater_slope_scope === :ability_only),
        item_slope_scope = pr.item_slope_scope,
        rater_slope_scope = pr.rater_slope_scope,
        aggregation = pr.aggregation,
        cross_loading_average = pr.cross_loading_average,
        logit_scale = s0,
        location_step_rank = loc_rank,
    )
end
design_matrices(f::Fit) = design_matrices(checked(f))

function facet_basis(t::Target, facet::Symbol = :item)
    pr = t.prior
    blk = facet === :entity ? :person : (facet === :criterion ? :item : (facet === :thresholds ? :steps : facet))
    if blk === :person
        counts = [count(==(p), t.person) for p in 1:t.P]
        return (;
            facet = :person,
            n_levels = t.P,
            dimensions = t.D,
            levels = copy(t.person_levels),
            observation_counts = counts,
            person_scale = :absolute,
            constraint = pr.location_identification === :zero_mean_population ?
                :population_zero_mean : :free_population_mean_with_centered_pure_items,
            raw_range = t.person_z_range,
            basis_matrix = Matrix{Float64}(I, t.P, t.P),
        )
    elseif blk === :item
        counts = [count(==(i), t.item) for i in 1:t.I]
        B_it = if pr.location_identification === :zero_mean_population
            Matrix{Float64}(I, t.I, t.I)
        else
            n_cols = sum(max(length(t.pure_items_by_dim[d]) - 1, 0) for d in 1:t.D; init = 0) + length(t.cross_items)
            M = zeros(Float64, t.I, n_cols)
            cc = 0
            for d in 1:t.D
                pitems = t.pure_items_by_dim[d]
                Id = length(pitems)
                if Id >= 2
                    Hd = _helmert_basis_matrix(Id)
                    for k in 1:(Id - 1)
                        cc += 1
                        for (m, idx_i) in enumerate(pitems)
                            M[idx_i, cc] = Hd[m, k]
                        end
                    end
                end
            end
            for idx_i in t.cross_items
                cc += 1
                M[idx_i, cc] = 1.0
            end
            M
        end
        return (;
            facet = facet === :criterion ? :criterion : :item,
            n_levels = t.I,
            levels = copy(t.item_levels),
            observation_counts = counts,
            constraint = pr.location_identification === :zero_mean_population ?
                :unconstrained_normal : :helmert_zero_sum_within_pure_dimension_items,
            prior_sd = pr.item_sd,
            basis_matrix = B_it,
        )
    elseif blk === :rater
        counts = [count(==(r), t.rater) for r in 1:t.R]
        return (;
            facet = :rater,
            n_levels = t.R,
            levels = copy(t.rater_levels),
            observation_counts = counts,
            constraint = :helmert_zero_sum,
            prior_sd = pr.rater_sd,
            raw_range = t.rater_range,
            basis_matrix = _helmert_basis_matrix(t.R),
        )
    elseif blk === :consistency
        counts = [count(==(r), t.rater) for r in 1:t.R]
        return (;
            facet = :consistency,
            n_levels = t.R,
            levels = copy(t.rater_levels),
            observation_counts = counts,
            scope = pr.rater_slope_scope,
            constraint = pr.rater_consistency === :fixed_one ? :fixed_one : :helmert_zero_sum_on_log_scale,
            prior_sd = pr.log_consistency_sd,
            raw_range = t.consistency_range,
            basis_matrix = pr.rater_consistency === :fixed_one ? zeros(Float64, t.R, 0) : _helmert_basis_matrix(t.R),
        )
    elseif blk === :loading
        counts = [count(==(i), t.item) for i in 1:t.I]
        return (;
            facet = :loading,
            n_levels = length(t.active_pairs),
            active_pairs = copy(t.active_pairs),
            q_matrix = copy(t.q_matrix),
            observation_counts = counts,
            scope = pr.item_slope_scope,
            constraint = pr.item_slopes === :fixed_one ? :fixed_one : pr.scale_identification,
            anchor_items = pr.scale_identification === :anchor_item ? [t.item_levels[i] for i in t.anchor_item_indices] : nothing,
            prior_sd = pr.log_loading_sd,
        )
    elseif blk === :steps
        return (;
            facet = :steps,
            step_owner = t.step_owner,
            n_groups = t.n_step_groups,
            group_levels = copy(t.step_group_levels),
            n_steps_per_group = t.H,
            constraint = :helmert_zero_sum_within_step_group,
            prior_sd = pr.step_sd,
            raw_ranges = copy(t.step_ranges),
            basis_matrix = _helmert_basis_matrix(t.H),
        )
    end
    throw(ArgumentError("facet must be :person (:entity), :item (:criterion), :rater, :consistency, :loading, or :steps"))
end
facet_basis(f::Fit, facet::Symbol = :item) = facet_basis(checked(f), facet)

function constraint_table(t::Target)
    pr = t.prior
    rows = NamedTuple[
        (;
            block = :person,
            constraint = pr.location_identification === :zero_mean_population ?
                :population_mean_fixed_zero : :free_population_mean_estimated_sd,
            scale_prior = pr.ability_sd_family,
            latent_correlation = pr.latent_correlation,
            n_free_parameters = length(t.person_z_range) + length(t.ability_mean_z_range) + length(t.ability_logsd_z_range) + length(t.corr_z_range),
        ),
        (;
            block = :loading,
            constraint = pr.item_slopes === :fixed_one ? :fixed_one : pr.scale_identification,
            scope = pr.item_slope_scope,
            anchor_items = pr.scale_identification === :anchor_item ? [t.item_levels[i] for i in t.anchor_item_indices] : nothing,
            n_free_parameters = sum(length, t.pure_loading_ranges; init = 0) + length(t.cross_loading_range) + length(t.anchor_free_loading_range),
        ),
        (;
            block = pr.item_role,
            constraint = pr.location_identification === :zero_mean_population ?
                :unconstrained : :zero_sum_pure_items_per_dimension,
            n_free_parameters = length(t.item_free_range) + sum(length, t.pure_item_ranges; init = 0) + length(t.cross_item_range),
        ),
        (;
            block = :rater,
            constraint = :zero_sum_isometric,
            n_free_parameters = length(t.rater_range),
        ),
        (;
            block = :consistency,
            constraint = pr.rater_consistency === :fixed_one ? :fixed_one : :geometric_mean_one_isometric,
            scope = pr.rater_slope_scope,
            n_free_parameters = length(t.consistency_range),
        ),
        (;
            block = :steps,
            constraint = :zero_sum_per_step_owner,
            step_owner = t.step_owner,
            n_free_parameters = sum(length, t.step_ranges; init = 0),
        ),
    ]
    if pr.aggregation === :softmin
        push!(rows, (;
            block = :aggregation,
            constraint = pr.softmin_kappa_mode === :fixed ? :fixed_softmin_kappa : :estimated_positive_softmin_kappa,
            scope = :cross_loaded_items,
            n_free_parameters = length(t.softmin_kappa_z_range),
        ))
    end
    return rows
end
constraint_table(f::Fit) = constraint_table(checked(f))

function _effective_unit_logit_prior_sd(pr::Prior)
    s0 = pr.logit_scale
    ab_scale = pr.ability_sd_family === :lognormal ? exp(pr.ability_logsd_mean) : pr.ability_sd_scale
    return (;
        logit_scale = s0,
        ability_sd_reference_unit_logit = s0 * ab_scale,
        ability_mean_sd_unit_logit = s0 * pr.ability_mean_sd,
        item_sd_unit_logit = s0 * pr.item_sd,
        rater_sd_unit_logit = s0 * pr.rater_sd,
        step_sd_unit_logit = s0 * pr.step_sd,
        log_loading_sd = pr.log_loading_sd,
        log_consistency_sd = pr.log_consistency_sd,
    )
end

function contract(t::Target)
    pr = t.prior
    p_measure = (pr.ability_sd_family === :lognormal && pr.latent_correlation === :identity_fixed) ?
        :standard_normal_white_coordinates_with_exact_jacobian_cancellation :
        :hybrid_white_logscale_and_lkj_cholesky_with_exact_jacobian
    base_ct = (;
        schema = "bayesianmgmfrm.scale_identified_mgmfrm_contract.v1",
        family = pr.family_tag,
        status = :experimental,
        dimensions = t.D,
        dimension_labels = copy(t.dimension_labels),
        logit_scale = pr.logit_scale,
        available_logit_scales = (1.7, 1.0),
        step_owner = t.step_owner,
        loading_scope = pr.item_slope_scope,
        rater_consistency_scope = pr.rater_slope_scope,
        rater_consistency = pr.rater_consistency,
        scale_identification = pr.scale_identification,
        available_scale_identifications = (:geometric_mean_one, :anchor_item, :prior_only),
        location_identification = pr.location_identification,
        available_location_identifications = (:zero_mean_population, :centered_items_free_mean),
        anchor_items = pr.scale_identification === :anchor_item ?
            [t.item_levels[i] for i in t.anchor_item_indices] : nothing,
        pure_items_per_dimension = Tuple(length(v) for v in t.pure_items_by_dim),
        n_cross_loaded_items = length(t.cross_items),
        latent_correlation = pr.latent_correlation,
        prior_measure = p_measure,
        prior_asymmetry_detected = pr.scale_identification === :anchor_item,
        label_permutation_invariant = pr.scale_identification === :geometric_mean_one,
        prior = prior_record(pr),
        n_raw_parameters = t.dimension,
        n_model_parameters = length(t.model_names),
        supported_backends = (:advancedhmc,),
        gradient_backends = (:analytic, :ForwardDiff),
        target_identity = target_identity(t),
        scientific_acceptance = false,
    )
    _is_v1_compatible_prior(pr) && return base_ct
    return merge(base_ct, (;
        ability_sd_family = pr.ability_sd_family,
        lkj_eta = pr.latent_correlation === :lkj ? pr.lkj_eta : nothing,
        item_slopes = pr.item_slopes,
        aggregation = pr.aggregation,
        cross_loading_average = pr.cross_loading_average,
        softmin_kappa_mode = pr.softmin_kappa_mode,
        person_scale = :absolute,
        effective_unit_logit_prior_sd = _effective_unit_logit_prior_sd(pr),
    ))
end

function design_summary(t::Target)
    base = B.design_summary(t.spec)
    dm = design_matrices(t)
    return merge(base, (;
        schema = "bayesianmgmfrm.scale_identified_mgmfrm_design_summary.v1",
        family = t.prior.family_tag,
        step_owner = t.step_owner,
        scale_identification = t.prior.scale_identification,
        location_identification = t.prior.location_identification,
        latent_correlation = t.prior.latent_correlation,
        lkj_eta = t.prior.latent_correlation === :lkj ? t.prior.lkj_eta : nothing,
        ability_sd_family = t.prior.ability_sd_family,
        item_slopes = t.prior.item_slopes,
        item_slope_scope = t.prior.item_slope_scope,
        rater_slope_scope = t.prior.rater_slope_scope,
        aggregation = t.prior.aggregation,
        cross_loading_average = t.prior.cross_loading_average,
        softmin_kappa_mode = t.prior.softmin_kappa_mode,
        logit_scale = t.prior.logit_scale,
        effective_unit_logit_prior_sd = _effective_unit_logit_prior_sd(t.prior),
        person_scale = :absolute,
        rater_consistency = t.prior.rater_consistency,
        pure_items_per_dimension = Tuple(length(v) for v in t.pure_items_by_dim),
        n_cross_loaded_items = length(t.cross_items),
        q_structure = q_structure_summary(t),
        location_step_design_rank = dm.location_step_rank,
        n_free_parameters = t.dimension,
        n_model_parameters = length(t.model_names),
    ))
end

function validate_design(t::Target; min_category_count::Int = 10, min_bridge_overlap::Int = 2)
    cr5 = B._cr5_validate_facet_spec(t.spec; min_category_count, min_bridge_overlap)
    obs_pd = falses(t.P, t.D)
    for n in 1:t.N
        p_n = t.person[n]
        for d in t.active_dims_of_item[t.item[n]]
            obs_pd[p_n, d] = true
        end
    end
    all_obs_dims = all(obs_pd)
    ge2_pure = all(v -> length(v) >= 2, t.pure_items_by_dim)
    dm = design_matrices(t)
    loc_rank = dm.location_step_rank
    q_struct = q_structure_summary(t)
    thin_confirmed = any(tb -> tb.status === :thin_bridge_confirmed, cr5.connectedness.thin_bridges)
    reasons = Symbol[]
    cr5.connectedness.score_conditioned_connected || push!(reasons, :score_conditioned_disconnected)
    loc_rank.full_rank || push!(reasons, :location_design_rank_deficient)
    thin_confirmed && push!(reasons, :thin_facet_bridge)
    if t.prior.family_tag === :mgmfrm
        ge2_pure || push!(reasons, :fewer_than_two_pure_items_per_dimension)
        t.prior.scale_identification === :anchor_item && push!(reasons, :anchor_item_scale_identification_experimental)
        t.D >= 2 && !all_obs_dims && push!(reasons, :person_missing_dimension_coverage)
        t.prior.aggregation === :softmin && !q_struct.compensation_separable_algebraically &&
            push!(reasons, :softmin_cross_items_lack_pure_anchored_persons)
    end
    warns = copy(cr5.warnings)
    if !loc_rank.full_rank
        push!(warns, "Generalized location-and-step design matrix is rank deficient (rank $(loc_rank.rank) < $(loc_rank.columns)); dependent columns: $(join(loc_rank.dependent_columns, ", ")).")
    end
    domain_scoped = (;
        regime_passed = isempty(reasons),
        location_design_full_rank = loc_rank.full_rank,
        thin_bridges_clear = !thin_confirmed,
        every_person_observed_in_all_dimensions = all_obs_dims,
        ge_2_pure_items_per_dimension = ge2_pure,
        reasons,
    )
    eff_m = merge(cr5.effective_model, (;
        family = t.prior.family_tag,
        paradigm = :bayesian,
        threshold_owner = t.step_owner,
        step_owner_spec = t.step_owner,
        location_mode = t.prior.location_identification,
        rater_slope_scope = t.prior.rater_slope_scope,
        aggregation = t.prior.aggregation,
        identification = t.prior.family_tag === :gmfrm ?
            (t.prior.scale_identification === :anchor_item ? :gmfrm_anchor_item : :gmfrm_isometric_geometric_mean_one) :
            t.prior.scale_identification,
    ))
    return merge(cr5, (;
        passed = t.spec.validation.passed && all(!isempty, t.pure_items_by_dim) && loc_rank.full_rank,
        identified = all(!isempty, t.pure_items_by_dim) && loc_rank.full_rank,
        warnings = warns,
        scale_identification = t.prior.scale_identification,
        location_identification = t.prior.location_identification,
        latent_correlation = t.prior.latent_correlation,
        rater_slope_scope = t.prior.rater_slope_scope,
        aggregation = t.prior.aggregation,
        pure_items_per_dimension = Tuple(length(v) for v in t.pure_items_by_dim),
        q_structure = q_struct,
        location_step_design_rank = loc_rank,
        label_permutation_invariant = t.prior.scale_identification === :geometric_mean_one,
        prior_asymmetry_detected = t.prior.scale_identification === :anchor_item,
        domain_scoped_regime = domain_scoped,
        effective_model = eff_m,
        spec_validation = t.spec.validation,
    ))
end

function prior_draw(t::Target; seed::Integer = 1, rng::Union{Nothing, AbstractRNG} = nothing)
    seed isa Integer && !(seed isa Bool) || throw(ArgumentError("seed must be an integer"))
    actual_rng = rng === nothing ? Random.MersenneTwister(Int(seed)) : rng
    q = randn(actual_rng, Float64, t.dimension)
    pr = t.prior
    if pr.ability_sd_family === :half_normal
        s = pr.ability_sd_scale
        for j in t.ability_logsd_z_range
            sig = max(abs(s * randn(actual_rng)), 1e-300)
            q[j] = log(sig)
        end
    elseif pr.ability_sd_family === :half_t
        s = pr.ability_sd_scale
        df = pr.ability_sd_df
        for j in t.ability_logsd_z_range
            z = randn(actual_rng)
            chi = rand(actual_rng, Chisq(df))
            sig = max(s * abs(z) / sqrt(chi / df), 1e-300)
            q[j] = log(sig)
        end
    end
    if pr.latent_correlation === :lkj
        for (k, j) in enumerate(t.corr_z_range)
            alpha_k = t.lkj_alphas[k]
            u_b = rand(actual_rng, Beta(alpha_k, alpha_k))
            z_k = clamp(2.0 * u_b - 1.0, -1.0 + 1e-15, 1.0 - 1e-15)
            q[j] = atanh(z_k)
        end
    end
    return q
end

function _category_probs_point(t::Target, c)
    probs = Matrix{Float64}(undef, t.N, t.K)
    logits = Vector{Float64}(undef, t.K)
    @inbounds for n in 1:t.N
        p, i, r = t.person[n], t.item[n], t.rater[n]
        g = t.step_group_of_obs[n]
        loc_z, alpha_z = _obs_loc_and_scale(t, c, p, i, r)
        loc = Float64(loc_z)
        alpha_obs = Float64(alpha_z)
        logits[1] = 0.0
        mx = 0.0
        for k in 2:t.K
            lk = logits[k - 1] + alpha_obs * (loc - Float64(c.steps[g, k - 1]))
            logits[k] = lk
            lk > mx && (mx = lk)
        end
        denom = 0.0
        for k in 1:t.K
            w = exp(logits[k] - mx)
            probs[n, k] = w
            denom += w
        end
        inv_d = 1.0 / denom
        for k in 1:t.K
            probs[n, k] *= inv_d
        end
    end
    return probs
end

function _simulate_draw_and_scores(
        t::Target,
        actual_rng::AbstractRNG,
        q::Union{Nothing, AbstractVector{<:Real}})
    q_vec = q === nothing ? prior_draw(t; rng = actual_rng) : Float64.(collect(q))
    _check_vector(t, q_vec)
    c = coordinates(t, q_vec)
    probs = _category_probs_point(t, c)
    scores = Vector{Int}(undef, t.N)
    cats = Vector{Int}(undef, t.N)
    @inbounds for n in 1:t.N
        u = rand(actual_rng)
        cum = 0.0
        chosen = t.K
        for k in 1:t.K
            cum += probs[n, k]
            if u <= cum
                chosen = k
                break
            end
        end
        cats[n] = chosen
        scores[n] = t.category_levels[chosen]
    end
    return q_vec, c, probs, scores, cats
end

function simulate(t::Target; seed::Integer = 1, q::Union{Nothing, AbstractVector{<:Real}} = nothing,
        rng::Union{Nothing, AbstractRNG} = nothing)
    seed isa Integer && !(seed isa Bool) || throw(ArgumentError("seed must be an integer"))
    actual_rng = rng === nothing ? Random.MersenneTwister(Int(seed)) : rng
    q_vec, c, probs, scores, cats = _simulate_draw_and_scores(t, actual_rng, q)
    sim_data = B.FacetData((
        person = [t.person_levels[t.person[n]] for n in 1:t.N],
        item = [t.item_levels[t.item[n]] for n in 1:t.N],
        rater = [t.rater_levels[t.rater[n]] for n in 1:t.N],
        score = scores,
    ); person = :person, item = :item, rater = :rater, score = :score,
       category_levels = t.category_levels)
    want_thresh = t.spec.thresholds
    sim_report = B.validate_design(sim_data)
    err_issues = [iss for iss in sim_report.issues if iss.severity === :error]
    sim_spec = if sim_report.passed || !all(iss -> iss.code === :single_observed_category, err_issues)
        B.mfrm_spec(sim_data;
            family = :mgmfrm,
            dimensions = t.D,
            thresholds = want_thresh,
            q_matrix = copy(t.q_matrix),
            dimension_labels = copy(t.dimension_labels),
        )
    else
        B.FacetSpec(
            sim_data,
            want_thresh,
            sim_report,
            :mgmfrm,
            t.D,
            copy(t.dimension_labels),
            t.spec.discrimination,
            copy(t.q_matrix),
            copy(t.spec.validation_bias_terms),
            copy(t.spec.anchors),
            deepcopy(t.spec.constraints),
            deepcopy(t.spec.prior_blocks),
            t.spec.estimation_status,
        )
    end
    return (;
        seed = Int(seed),
        q = q_vec,
        truth = c,
        probabilities = probs,
        scores,
        categories = cats,
        data = sim_data,
        spec = sim_spec,
        target = model(sim_spec; prior = t.prior),
    )
end

function prior_predictive_check(t::Target; ndraws::Int = 100, seed::Integer = 1,
        rng::Union{Nothing, AbstractRNG} = nothing)
    ndraws >= 1 || throw(ArgumentError("ndraws must be >= 1"))
    seed isa Integer && !(seed isa Bool) || throw(ArgumentError("seed must be an integer"))
    actual_rng = rng === nothing ? Random.MersenneTwister(Int(seed)) : rng
    raw_draws = Matrix{Float64}(undef, ndraws, t.dimension)
    replicated_scores = Matrix{Int}(undef, ndraws, t.N)
    rep_props = Matrix{Float64}(undef, ndraws, t.K)
    for s in 1:ndraws
        q_vec, _, _, scores, cats = _simulate_draw_and_scores(t, actual_rng, nothing)
        raw_draws[s, :] .= q_vec
        replicated_scores[s, :] .= scores
        for k in 1:t.K
            rep_props[s, k] = count(==(k), cats) / t.N
        end
    end
    obs_props = [count(==(k), t.category) / t.N for k in 1:t.K]
    rows = [
        (;
            category = t.category_levels[k],
            observed_proportion = obs_props[k],
            prior_mean = mean(view(rep_props, :, k)),
            prior_q05 = quantile(view(rep_props, :, k), 0.05),
            prior_q50 = quantile(view(rep_props, :, k), 0.50),
            prior_q95 = quantile(view(rep_props, :, k), 0.95),
        ) for k in 1:t.K
    ]
    return (;
        schema = "bayesianmgmfrm.scale_identified_mgmfrm_prior_predictive.v1",
        ndraws,
        seed = Int(seed),
        target_identity = target_identity(t),
        prior = prior_record(t.prior),
        raw_parameter_draws = raw_draws,
        replicated_scores,
        rows,
    )
end

# ---------------------------------------------------------------------------
# Fitting, Verification, Diagnostics, Summaries & Persistence
# ---------------------------------------------------------------------------

function checked(f::Fit; full::Bool = false)
    r = f.record
    keys(r) == (:schema, :target, :target_identity, :run, :producer, :content_hash) &&
        r.schema == FIT_SCHEMA ||
        throw(ArgumentError("unsupported scale-identified MGMFRM fit record"))
    body = (; r.schema, r.target, r.target_identity, r.run, r.producer)
    B._cache_hash(body) == r.content_hash ||
        throw(ArgumentError("scale-identified MGMFRM fit content_hash mismatch"))
    t = restore_target(r.target)
    target_identity(t) == r.target_identity ||
        throw(ArgumentError("scale-identified MGMFRM target_identity mismatch"))
    if full
        B._check_generalized_sample_run(t, r.run)
        length(r.run.warmup_stats) == r.run.controls.chains * r.run.controls.warmup ||
            throw(ArgumentError("incomplete warmup telemetry in scale-identified MGMFRM fit"))
        B._warmup_diagnostic_rows(r.run.warmup_stats, r.run.controls, r.run.backend)
    end
    return t
end

# ---------------------------------------------------------------------------
# Orthogonal-Decoupled & PRS Reference-Design Person-Centered Sampling Chart
# ---------------------------------------------------------------------------

function _resolve_person_centered_dims(t::Target, choice)
    non_v1_person = t.prior.latent_correlation === :lkj || t.prior.ability_sd_family !== :lognormal
    if choice === :noncentered
        return falses(t.D)
    elseif choice === :centered
        non_v1_person && throw(ArgumentError(
            "person_coordinates = :centered applies only to independent LogNormal ability-SD targets; use :noncentered or :auto"))
        return fill(t.P >= 2, t.D)
    elseif choice isa AbstractVector{Bool}
        length(choice) == t.D || throw(ArgumentError("person_coordinates boolean mask length $(length(choice)) != D ($(t.D))"))
        (non_v1_person && any(choice)) && throw(ArgumentError(
            "person_coordinates centered dimensions apply only to independent LogNormal ability-SD targets"))
        return Bool[choice[d] && t.P >= 2 for d in 1:t.D]
    end
    cutoff = if choice === :auto
        8.0
    elseif choice isa NamedTuple && keys(choice) == (:information_cutoff,)
        c = choice.information_cutoff
        c isa Real && !(c isa Bool) && isfinite(c) && c > 0 ||
            throw(ArgumentError("person_coordinates information_cutoff must be a finite positive real"))
        Float64(c)
    else
        throw(ArgumentError("person_coordinates must be :auto, :noncentered, :centered, a Bool vector of length D, or (information_cutoff = value,)"))
    end
    (t.P < 2 || non_v1_person) && return falses(t.D)
    # Prior-only Papaspiliopoulos-Roberts-Skold (2007) reference-design information per person/dim.
    # Outcome values `y` NEVER enter this calculation!
    i1 = t.prior.logit_scale^2 * Float64(t.K^2 - 1) / 12.0
    sigma0_sq = exp(2.0 * t.prior.ability_logsd_mean)
    counts = zeros(Int, t.P, t.D)
    @inbounds for n in 1:t.N
        p = t.person[n]
        i = t.item[n]
        for d in t.active_dims_of_item[i]
            counts[p, d] += 1
        end
    end
    centered = Vector{Bool}(undef, t.D)
    for d in 1:t.D
        med_n = median(view(counts, :, d))
        centered[d] = (med_n * i1 * sigma0_sq) >= cutoff
    end
    return centered
end

struct SamplingTarget
    base::Target
    centered_dims::Vector{Bool}
    use_loc::Bool
    use_givens_mean::Bool
    use_anc::Bool
    reflector::Vector{Float64}
end

function SamplingTarget(base::Target; person_coordinates = :auto)
    centered_dims = _resolve_person_centered_dims(base, person_coordinates)
    pr = base.prior
    use_loc = pr.location_identification === :zero_mean_population &&
              pr.latent_correlation === :identity_fixed &&
              pr.ability_sd_family === :lognormal &&
              base.P >= 2
    use_givens_mean = pr.location_identification === :centered_items_free_mean &&
                      base.P >= 2 && !any(centered_dims)
    use_anc = pr.scale_identification === :anchor_item &&
              pr.ability_sd_family === :lognormal &&
              !isempty(base.anchor_free_loading_pairs)
    v = if use_loc || use_givens_mean
        w = fill(-inv(sqrt(Float64(base.P))), base.P)
        w[1] += 1.0
        w ./= norm(w)
        w
    else
        Float64[]
    end
    return SamplingTarget(base, centered_dims, use_loc, use_givens_mean, use_anc, v)
end

function _tiny_cholesky_L(S::AbstractMatrix{Z}) where {Z}
    D = size(S, 1)
    L_out = zeros(Z, D, D)
    @inbounds for i in 1:D
        for j in 1:(i - 1)
            acc = S[i, j]
            for k in 1:(j - 1)
                acc -= L_out[i, k] * L_out[j, k]
            end
            L_out[i, j] = acc / L_out[j, j]
        end
        diag_acc = S[i, i]
        for k in 1:(i - 1)
            diag_acc -= L_out[i, k] * L_out[i, k]
        end
        L_out[i, i] = sqrt(diag_acc)
    end
    return L_out
end

function _rdiv_lower_transpose(A::AbstractMatrix{Z}, C::AbstractMatrix{Z}) where {Z}
    m, D = size(A)
    X = zeros(Z, m, D)
    @inbounds for j in 1:D
        inv_cjj = inv(C[j, j])
        for i in 1:m
            acc = A[i, j]
            for k in 1:(j - 1)
                acc -= X[i, k] * C[j, k]
            end
            X[i, j] = acc * inv_cjj
        end
    end
    return X
end

# Smooth SO(2D) orthogonal matrix Q(B) decoupling ability_mean from the likelihood nullspace
# for arbitrary draw-specific (sigma_theta, L_corr) with exact unit Jacobian (log|det J| == 0).
function _lkj_orth_block(pr::Prior, P::Int, D::Int, w_logsd::AbstractVector, w_corr::AbstractVector)
    Z = promote_type(Float64, eltype(w_logsd), eltype(w_corr))
    inv_sqrt_p = inv(sqrt(Float64(P)))
    tau_mu = pr.ability_mean_sd
    sig = Vector{Z}(undef, D)
    if pr.ability_sd_family === :lognormal
        @inbounds for d in 1:D
            sig[d] = exp(pr.ability_logsd_mean + pr.ability_logsd_sd * w_logsd[d])
        end
    else
        @inbounds for d in 1:D
            sig[d] = exp(Z(w_logsd[d]))
        end
    end
    L_c = zeros(Z, D, D)
    L_c[1, 1] = one(Z)
    k_c = 0
    for i_d in 2:D
        log_rem = zero(Z)
        for j_d in 1:(i_d - 1)
            k_c += 1
            qk = w_corr[k_c]
            z_ij = tanh(qk)
            log_delta = _logsech2(qk)
            L_c[i_d, j_d] = z_ij * exp(0.5 * log_rem)
            log_rem += log_delta
        end
        L_c[i_d, i_d] = exp(0.5 * log_rem)
    end
    B_mat = zeros(Z, D, D)
    @inbounds for i_d in 1:D, j_d in 1:i_d
        B_mat[i_d, j_d] = (sig[i_d] * inv_sqrt_p) * L_c[i_d, j_d]
    end
    tau2 = tau_mu * tau_mu
    S1 = B_mat * transpose(B_mat)
    S2 = transpose(B_mat) * B_mat
    @inbounds for d in 1:D
        S1[d, d] += tau2
        S2[d, d] += tau2
    end
    C1 = _tiny_cholesky_L(S1)
    C2 = _tiny_cholesky_L(S2)
    Id_Z = Matrix{Z}(I, D, D)
    Q11 = _rdiv_lower_transpose(tau_mu .* Id_Z, C1)
    Q21 = _rdiv_lower_transpose(Matrix{Z}(transpose(B_mat)), C1)
    Q12 = _rdiv_lower_transpose(-B_mat, C2)
    Q22 = _rdiv_lower_transpose(tau_mu .* Id_Z, C2)
    Q = zeros(Z, 2 * D, 2 * D)
    Q[1:D, 1:D] .= Q11
    Q[(D + 1):(2 * D), 1:D] .= Q21
    Q[1:D, (D + 1):(2 * D)] .= Q12
    Q[(D + 1):(2 * D), (D + 1):(2 * D)] .= Q22
    return Q
end

L.dimension(st::SamplingTarget) = st.base.dimension
L.capabilities(::Type{SamplingTarget}) = L.LogDensityOrder{1}()
B._check_source_fixture_raw_vector(st::SamplingTarget, u::AbstractVector) = _check_vector(st.base, u)

function _anc_to_mid(st::SamplingTarget, u::AbstractVector)
    w = u .+ 0.0
    if st.use_anc
        t = st.base
        kappa = t.prior.ability_logsd_sd / t.prior.log_loading_sd
        @inbounds for (m, (_, d)) in enumerate(t.anchor_free_loading_pairs)
            ja = t.anchor_free_loading_range[m]
            js = t.ability_logsd_z_range[d]
            w[ja] = u[ja] - kappa * u[js]
        end
    end
    return w
end

function _to_raw_with_logjac(st::SamplingTarget, u::AbstractVector)
    _check_vector(st.base, u)
    w = _anc_to_mid(st, u)
    any_cp = any(st.centered_dims)
    (!st.use_loc && !st.use_givens_mean && !any_cp) && return (w, zero(eltype(w)))
    t = st.base
    pr = t.prior
    Z = eltype(w)
    q = copy(w)
    P, D, I = t.P, t.D, t.I
    inv_sqrt_p = inv(sqrt(Float64(P)))

    if st.use_givens_mean
        refl = st.reflector
        if pr.latent_correlation === :lkj
            u_vec = Vector{Z}(undef, 2 * D)
            @inbounds for d in 1:D
                u_vec[d] = w[t.ability_mean_z_range[d]]
                u_vec[D + d] = w[d]
            end
            Q_orth = _lkj_orth_block(pr, P, D, view(w, t.ability_logsd_z_range), view(w, t.corr_z_range))
            q_vec = Q_orth * u_vec
            @inbounds for d in 1:D
                q[t.ability_mean_z_range[d]] = q_vec[d]
                qt_d = q_vec[D + d]
                dot_v = refl[1] * qt_d
                for p in 2:P
                    dot_v += refl[p] * w[(p - 1) * D + d]
                end
                two_dot = 2.0 * dot_v
                q[d] = qt_d - two_dot * refl[1]
                for p in 2:P
                    idx = (p - 1) * D + d
                    q[idx] = w[idx] - two_dot * refl[p]
                end
            end
        else
            tau_mu = pr.ability_mean_sd
            @inbounds for d in 1:D
                j_sd = t.ability_logsd_z_range[d]
                lsd = pr.ability_sd_family === :lognormal ?
                    (pr.ability_logsd_mean + pr.ability_logsd_sd * w[j_sd]) : Z(w[j_sd])
                s_bar = exp(lsd) * inv_sqrt_p
                r_d = hypot(tau_mu, s_bar)
                c_d = tau_mu / r_d
                s_d = s_bar / r_d
                j_mu = t.ability_mean_z_range[d]
                u_mu = w[j_mu]
                u_tilde = w[d]
                q_mu = c_d * u_mu - s_d * u_tilde
                q_tilde = s_d * u_mu + c_d * u_tilde
                q[j_mu] = q_mu
                dot_v = refl[1] * q_tilde
                for p in 2:P
                    dot_v += refl[p] * w[(p - 1) * D + d]
                end
                two_dot = 2.0 * dot_v
                q[d] = q_tilde - two_dot * refl[1]
                for p in 2:P
                    idx = (p - 1) * D + d
                    q[idx] = w[idx] - two_dot * refl[p]
                end
            end
        end
        return (q, zero(Z))
    end

    bar_shift = Vector{Z}(undef, D)
    log_jac = zero(Z)

    @inbounds for d in 1:D
        log_sd = pr.ability_logsd_mean + pr.ability_logsd_sd * w[t.ability_logsd_z_range[d]]
        inv_sig = exp(-log_sd)
        is_cp = st.centered_dims[d]
        is_cp && (log_jac -= P * log_sd)
        s_fac = is_cp ? inv_sig : one(Z)
        if st.use_loc
            bar_shift[d] = w[d] * inv_sqrt_p
            dot_v = zero(Z)
            for p in 1:P
                dot_v += st.reflector[p] * w[(p - 1) * D + d]
            end
            two_dot = 2.0 * dot_v
            for p in 1:P
                idx = (p - 1) * D + d
                q[idx] = s_fac * (w[idx] - two_dot * st.reflector[p])
            end
        elseif is_cp
            for p in 1:P
                idx = (p - 1) * D + d
                q[idx] = inv_sig * w[idx]
            end
        end
    end

    if st.use_loc
        c_w = coordinates(t, w)
        inv_isd = inv(pr.item_sd)
        @inbounds for i in 1:I
            shift = zero(Z)
            for d in t.active_dims_of_item[i]
                coef = st.centered_dims[d] ? c_w.loading[i, d] : c_w.standardized_loading[i, d]
                shift += coef * bar_shift[d]
            end
            ji = t.item_free_range[i]
            q[ji] = w[ji] + inv_isd * shift
        end
    end
    return (q, log_jac)
end

to_raw(st::SamplingTarget, u::AbstractVector) = first(_to_raw_with_logjac(st, u))

function from_raw(st::SamplingTarget, q::AbstractVector)
    _check_vector(st.base, q)
    t = st.base
    pr = t.prior
    w = q .+ 0.0
    Z = eltype(w)
    P, D, I = t.P, t.D, t.I
    inv_sqrt_p = inv(sqrt(Float64(P)))

    if st.use_givens_mean
        refl = st.reflector
        if pr.latent_correlation === :lkj
            q_vec = Vector{Z}(undef, 2 * D)
            @inbounds for d in 1:D
                q_vec[d] = q[t.ability_mean_z_range[d]]
                dot_v = zero(Z)
                for p in 1:P
                    dot_v += refl[p] * q[(p - 1) * D + d]
                end
                two_dot = 2.0 * dot_v
                q_vec[D + d] = q[d] - two_dot * refl[1]
                for p in 2:P
                    idx = (p - 1) * D + d
                    w[idx] = q[idx] - two_dot * refl[p]
                end
            end
            Q_orth = _lkj_orth_block(pr, P, D, view(q, t.ability_logsd_z_range), view(q, t.corr_z_range))
            u_vec = transpose(Q_orth) * q_vec
            @inbounds for d in 1:D
                w[t.ability_mean_z_range[d]] = u_vec[d]
                w[d] = u_vec[D + d]
            end
        else
            tau_mu = pr.ability_mean_sd
            @inbounds for d in 1:D
                j_sd = t.ability_logsd_z_range[d]
                lsd = pr.ability_sd_family === :lognormal ?
                    (pr.ability_logsd_mean + pr.ability_logsd_sd * q[j_sd]) : Z(q[j_sd])
                s_bar = exp(lsd) * inv_sqrt_p
                r_d = hypot(tau_mu, s_bar)
                c_d = tau_mu / r_d
                s_d = s_bar / r_d
                j_mu = t.ability_mean_z_range[d]
                q_mu = q[j_mu]
                dot_v = zero(Z)
                for p in 1:P
                    dot_v += refl[p] * q[(p - 1) * D + d]
                end
                two_dot = 2.0 * dot_v
                q_tilde = q[d] - two_dot * refl[1]
                for p in 2:P
                    idx = (p - 1) * D + d
                    w[idx] = q[idx] - two_dot * refl[p]
                end
                w[j_mu] = c_d * q_mu + s_d * q_tilde
                w[d] = -s_d * q_mu + c_d * q_tilde
            end
        end
    else
        bar_shift = Vector{Z}(undef, D)
        @inbounds for d in 1:D
            log_sd = pr.ability_logsd_mean + pr.ability_logsd_sd * q[t.ability_logsd_z_range[d]]
            sig = exp(log_sd)
            is_cp = st.centered_dims[d]
            s_fac = is_cp ? sig : one(Z)
            if st.use_loc
                dot_v = zero(Z)
                for p in 1:P
                    dot_v += st.reflector[p] * (s_fac * q[(p - 1) * D + d])
                end
                two_dot = 2.0 * dot_v
                for p in 1:P
                    idx = (p - 1) * D + d
                    w[idx] = s_fac * q[idx] - two_dot * st.reflector[p]
                end
                bar_shift[d] = w[d] * inv_sqrt_p
            elseif is_cp
                for p in 1:P
                    idx = (p - 1) * D + d
                    w[idx] = sig * q[idx]
                end
            end
        end
        if st.use_loc
            c_q = coordinates(t, q)
            inv_isd = inv(pr.item_sd)
            @inbounds for i in 1:I
                shift = zero(Z)
                for d in t.active_dims_of_item[i]
                    coef = st.centered_dims[d] ? c_q.loading[i, d] : c_q.standardized_loading[i, d]
                    shift += coef * bar_shift[d]
                end
                ji = t.item_free_range[i]
                w[ji] = q[ji] - inv_isd * shift
            end
        end
    end

    u = copy(w)
    if st.use_anc
        kappa = pr.ability_logsd_sd / pr.log_loading_sd
        @inbounds for (m, (_, d)) in enumerate(t.anchor_free_loading_pairs)
            ja = t.anchor_free_loading_range[m]
            js = t.ability_logsd_z_range[d]
            u[ja] = w[ja] + kappa * w[js]
        end
    end
    return u
end

function L.logdensity(st::SamplingTarget, u::AbstractVector)
    q, lj = _to_raw_with_logjac(st, u)
    return L.logdensity(st.base, q) + lj
end

@inline function _helmert_transpose_add!(
        g_dest::AbstractVector{Float64},
        g_sub::AbstractVector{Float64},
        scale::Float64)
    m = length(g_dest)
    pref = g_sub[1]
    @inbounds for k in 1:m
        g_dest[k] += scale * ((pref - Float64(k) * g_sub[k + 1]) / sqrt(Float64(k) * Float64(k + 1)))
        pref += g_sub[k + 1]
    end
    return g_dest
end

function L.logdensity_and_gradient(st::SamplingTarget, u::AbstractVector)
    _check_vector(st.base, u)
    any_cp = any(st.centered_dims)
    (!st.use_loc && !st.use_givens_mean && !st.use_anc && !any_cp) && return L.logdensity_and_gradient(st.base, u)
    t = st.base
    pr = t.prior
    P, D, I, dim = t.P, t.D, t.I, t.dimension
    sc = _get_scale_id_grad_scratch(t)

    w = sc.w_buf
    @inbounds for j in 1:dim
        w[j] = Float64(u[j])
    end
    if st.use_anc
        kappa = pr.ability_logsd_sd / pr.log_loading_sd
        @inbounds for (m, (_, d)) in enumerate(t.anchor_free_loading_pairs)
            ja = t.anchor_free_loading_range[m]
            js = t.ability_logsd_z_range[d]
            w[ja] -= kappa * w[js]
        end
    end

    q = sc.q_buf
    copyto!(q, w)
    inv_sqrt_p = inv(sqrt(Float64(P)))
    lj = 0.0

    if st.use_givens_mean
        refl = st.reflector
        if pr.latent_correlation === :lkj
            u_vec = Vector{Float64}(undef, 2 * D)
            @inbounds for d in 1:D
                u_vec[d] = w[t.ability_mean_z_range[d]]
                u_vec[D + d] = w[d]
            end
            w_sd_slice = view(w, t.ability_logsd_z_range)
            w_cr_slice = view(w, t.corr_z_range)
            Q_orth = _lkj_orth_block(pr, P, D, w_sd_slice, w_cr_slice)
            q_vec = Q_orth * u_vec
            @inbounds for d in 1:D
                q[t.ability_mean_z_range[d]] = q_vec[d]
                qt_d = q_vec[D + d]
                dot_v = refl[1] * qt_d
                for p in 2:P
                    dot_v += refl[p] * w[(p - 1) * D + d]
                end
                two_dot = 2.0 * dot_v
                q[d] = qt_d - two_dot * refl[1]
                for p in 2:P
                    idx = (p - 1) * D + d
                    q[idx] = w[idx] - two_dot * refl[p]
                end
            end
            lp_base, g_q = L.logdensity_and_gradient(t, q)
            gq_vec = Vector{Float64}(undef, 2 * D)
            g_w = g_q
            @inbounds for d in 1:D
                gq_vec[d] = g_q[t.ability_mean_z_range[d]]
                dot_gv = 0.0
                for p in 1:P
                    dot_gv += refl[p] * g_q[(p - 1) * D + d]
                end
                two_gv = 2.0 * dot_gv
                gq_vec[D + d] = g_q[d] - two_gv * refl[1]
                for p in 2:P
                    idx = (p - 1) * D + d
                    g_w[idx] = g_q[idx] - two_gv * refl[p]
                end
            end
            gw_vec = transpose(Q_orth) * gq_vec
            n_cr = length(t.corr_z_range)
            v_in = vcat(Float64.(w_sd_slice), Float64.(w_cr_slice))
            g_v = B.ForwardDiff.gradient(v_in) do v
                Qv = _lkj_orth_block(pr, P, D, view(v, 1:D), view(v, (D + 1):(D + n_cr)))
                dot(gq_vec, Qv * u_vec)
            end
            @inbounds for d in 1:D
                g_w[t.ability_mean_z_range[d]] = gw_vec[d]
                g_w[d] = gw_vec[D + d]
                g_w[t.ability_logsd_z_range[d]] += g_v[d]
            end
            @inbounds for k_c in 1:n_cr
                g_w[t.corr_z_range[k_c]] += g_v[D + k_c]
            end
        else
            tau_mu = pr.ability_mean_sd
            dlogsd_dw = pr.ability_sd_family === :lognormal ? pr.ability_logsd_sd : 1.0
            @inbounds for d in 1:D
                j_sd = t.ability_logsd_z_range[d]
                lsd = pr.ability_sd_family === :lognormal ?
                    (pr.ability_logsd_mean + pr.ability_logsd_sd * w[j_sd]) : w[j_sd]
                s_bar = exp(lsd) * inv_sqrt_p
                r_d = hypot(tau_mu, s_bar)
                c_d = tau_mu / r_d
                s_d = s_bar / r_d
                sc.mu_theta[d] = c_d
                sc.sigma_theta[d] = s_d
                j_mu = t.ability_mean_z_range[d]
                u_mu = w[j_mu]
                u_tilde = w[d]
                q_mu = c_d * u_mu - s_d * u_tilde
                q_tilde = s_d * u_mu + c_d * u_tilde
                sc.bar_shift[d] = q_tilde
                q[j_mu] = q_mu
                dot_v = refl[1] * q_tilde
                for p in 2:P
                    dot_v += refl[p] * w[(p - 1) * D + d]
                end
                two_dot = 2.0 * dot_v
                q[d] = q_tilde - two_dot * refl[1]
                for p in 2:P
                    idx = (p - 1) * D + d
                    q[idx] = w[idx] - two_dot * refl[p]
                end
            end
            q_mu_saved = Float64[q[t.ability_mean_z_range[d]] for d in 1:D]
            q_tilde_saved = Float64[sc.bar_shift[d] for d in 1:D]
            c_saved = Float64[sc.mu_theta[d] for d in 1:D]
            s_saved = Float64[sc.sigma_theta[d] for d in 1:D]
            lp_base, g_q = L.logdensity_and_gradient(t, q)
            g_w = g_q
            @inbounds for d in 1:D
                c_d = c_saved[d]
                s_d = s_saved[d]
                j_mu = t.ability_mean_z_range[d]
                gq_mu = g_q[j_mu]
                dot_gv = 0.0
                for p in 1:P
                    dot_gv += refl[p] * g_q[(p - 1) * D + d]
                end
                two_gv = 2.0 * dot_gv
                gq_tilde = g_q[d] - two_gv * refl[1]
                for p in 2:P
                    idx = (p - 1) * D + d
                    g_w[idx] = g_q[idx] - two_gv * refl[p]
                end
                g_w[j_mu] = c_d * gq_mu + s_d * gq_tilde
                g_w[d] = -s_d * gq_mu + c_d * gq_tilde
                g_w[t.ability_logsd_z_range[d]] += dlogsd_dw * (c_d * s_d * (gq_tilde * q_mu_saved[d] - gq_mu * q_tilde_saved[d]))
            end
        end
        if st.use_anc
            kappa = pr.ability_logsd_sd / pr.log_loading_sd
            @inbounds for (m, (_, d)) in enumerate(t.anchor_free_loading_pairs)
                ja = t.anchor_free_loading_range[m]
                js = t.ability_logsd_z_range[d]
                g_w[js] -= kappa * g_w[ja]
            end
        end
        return (lp_base, g_w)
    end

    bar_shift = sc.bar_shift
    @inbounds for d in 1:D
        log_sd = pr.ability_logsd_mean + pr.ability_logsd_sd * w[t.ability_logsd_z_range[d]]
        sig = exp(log_sd)
        sc.sigma_theta[d] = sig
        inv_sig = inv(sig)
        is_cp = st.centered_dims[d]
        is_cp && (lj -= Float64(P) * log_sd)
        s_fac = is_cp ? inv_sig : 1.0
        if st.use_loc
            bar_shift[d] = w[d] * inv_sqrt_p
            dot_v = 0.0
            for p in 1:P
                dot_v += st.reflector[p] * w[(p - 1) * D + d]
            end
            two_dot = 2.0 * dot_v
            for p in 1:P
                idx = (p - 1) * D + d
                q[idx] = s_fac * (w[idx] - two_dot * st.reflector[p])
            end
        elseif is_cp
            for p in 1:P
                idx = (p - 1) * D + d
                q[idx] = inv_sig * w[idx]
            end
        end
    end

    if st.use_loc
        _eval_loadings_f64!(sc.a_mat, sc.log_a, sc.tmp_buf, t, w)
        inv_isd = inv(pr.item_sd)
        @inbounds for i in 1:I
            shift = 0.0
            for d in t.active_dims_of_item[i]
                aid = sc.a_mat[i, d]
                coef = st.centered_dims[d] ? aid : (aid * sc.sigma_theta[d])
                shift += coef * bar_shift[d]
            end
            ji = t.item_free_range[i]
            q[ji] = w[ji] + inv_isd * shift
        end
    end

    lp_base, g_q = L.logdensity_and_gradient(t, q)
    lp = lp_base + lj
    g_w = g_q

    if st.use_loc
        @inbounds for d in 1:D
            is_cp = st.centered_dims[d]
            s_fac = is_cp ? inv(sc.sigma_theta[d]) : 1.0
            if is_cp
                dot_gq_q = 0.0
                for p in 1:P
                    idx = (p - 1) * D + d
                    dot_gq_q += g_q[idx] * q[idx]
                end
                g_w[t.ability_logsd_z_range[d]] += (-dot_gq_q - Float64(P)) * pr.ability_logsd_sd
            end
            dot_gv = 0.0
            for p in 1:P
                dot_gv += st.reflector[p] * (s_fac * g_q[(p - 1) * D + d])
            end
            two_dot = 2.0 * dot_gv
            for p in 1:P
                idx = (p - 1) * D + d
                g_w[idx] = s_fac * g_q[idx] - two_dot * st.reflector[p]
            end
        end

        g_bar = fill!(sc.g_bar, 0.0)
        g_log_a_extra = fill!(sc.g_log_a_extra, 0.0)
        g_sig_extra = fill!(sc.g_sig_extra, 0.0)
        inv_isd = inv(pr.item_sd)

        @inbounds for i in 1:I
            gamma_i = g_q[t.item_free_range[i]] * inv_isd
            for d in t.active_dims_of_item[i]
                is_cp = st.centered_dims[d]
                aid = sc.a_mat[i, d]
                coef = is_cp ? aid : (aid * sc.sigma_theta[d])
                g_bar[d] += gamma_i * coef
                term = coef * (gamma_i * bar_shift[d])
                g_log_a_extra[i, d] += term
                is_cp || (g_sig_extra[d] += term)
            end
        end

        @inbounds for d in 1:D
            g_w[d] += g_bar[d] * inv_sqrt_p
            g_w[t.ability_logsd_z_range[d]] += pr.ability_logsd_sd * g_sig_extra[d]
        end

        if pr.scale_identification === :geometric_mean_one
            for d in 1:D
                pitems = t.pure_items_by_dim[d]
                Id = length(pitems)
                if Id >= 2
                    g_sub = view(sc.tmp_buf, 1:Id)
                    @inbounds for (m, i) in enumerate(pitems)
                        g_sub[m] = g_log_a_extra[i, d]
                    end
                    _helmert_transpose_add!(view(g_w, t.pure_loading_ranges[d]), g_sub, t.pure_loading_scales[d])
                end
            end
            @inbounds for (m, (i, d)) in enumerate(t.cross_loading_pairs)
                g_w[t.cross_loading_range[m]] += pr.log_loading_sd * g_log_a_extra[i, d]
            end
        else
            @inbounds for (m, (i, d)) in enumerate(t.anchor_free_loading_pairs)
                g_w[t.anchor_free_loading_range[m]] += pr.log_loading_sd * g_log_a_extra[i, d]
            end
        end
    elseif any_cp
        @inbounds for d in 1:D
            st.centered_dims[d] || continue
            inv_sig = inv(sc.sigma_theta[d])
            dot_gq_q = 0.0
            for p in 1:P
                idx = (p - 1) * D + d
                dot_gq_q += g_q[idx] * q[idx]
                g_w[idx] = inv_sig * g_q[idx]
            end
            g_w[t.ability_logsd_z_range[d]] += (-dot_gq_q - Float64(P)) * pr.ability_logsd_sd
        end
    end

    g_u = g_w
    if st.use_anc
        kappa = pr.ability_logsd_sd / pr.log_loading_sd
        @inbounds for (m, (_, d)) in enumerate(t.anchor_free_loading_pairs)
            ja = t.anchor_free_loading_range[m]
            js = t.ability_logsd_z_range[d]
            g_u[js] -= kappa * g_w[ja]
        end
    end
    return (lp, g_u)
end

function fit(target::Target;
        ndraws::Int = 1000,
        warmup::Int = 800,
        chains::Int = 4,
        seed::Union{Nothing, Integer} = 1,
        rng::AbstractRNG = Random.default_rng(),
        init::Union{Nothing, AbstractVector{<:Real}} = nothing,
        target_accept::Union{Nothing, Real} = nothing,
        adapt_delta::Union{Nothing, Real} = nothing,
        max_depth::Union{Nothing, Int} = nothing,
        max_treedepth::Union{Nothing, Int} = nothing,
        step_size::Real = 0.03,
        init_jitter::Real = 0.1,
        metric::Symbol = :diagonal,
        ad_backend::Symbol = :auto,
        backend::Symbol = :advancedhmc,
        sampling_coordinates::Symbol = :orthogonal_decoupled,
        person_coordinates = :noncentered,
        progress::Union{Bool, B.SamplingProgress} = false,
        chain_execution::Symbol = :auto,
        max_parallel_chains::Int = chains,
        rhat_threshold::Real = 1.01,
        ess_threshold::Real = 400)
    backend === :advancedhmc || throw(ArgumentError(
        "ScaleIdentifiedMGMFRM.fit uses backend = :advancedhmc; for external CmdStan sampling use ScaleIdentifiedMGMFRM.stan_code(target) + stan_data(target) with StanAdapter.fit_stan"))
    ad_backend in (:auto, :analytic, :ForwardDiff) || throw(ArgumentError(
        "ad_backend must be :auto, :analytic, or :ForwardDiff; got $(repr(ad_backend))"))
    sampling_coordinates in (:orthogonal_decoupled, :raw) || throw(ArgumentError(
        "sampling_coordinates must be :orthogonal_decoupled or :raw; got $(repr(sampling_coordinates))"))
    resolved_ad = ad_backend === :auto ? :analytic : ad_backend
    def_ta = (target.prior.latent_correlation === :lkj && target.D == 3) ? 0.95 : 0.90
    ta_res, md_res = B._resolve_stan_nuts_aliases(;
        target_accept, adapt_delta, default_target_accept = def_ta,
        max_depth, max_treedepth, default_max_depth = 10,
        caller = "fit", backend = :advancedhmc)
    t = restore_target(target_record(target))
    initial = init === nothing ? zeros(Float64, t.dimension) : Float64.(collect(init))
    _check_vector(t, initial)
    if seed !== nothing
        seed isa Integer && !(seed isa Bool) && 0 <= seed <= typemax(Int) ||
            throw(ArgumentError("seed must be a nonnegative integer representable as Int"))
    end
    st = SamplingTarget(t; person_coordinates)
    use_decoupled = sampling_coordinates === :orthogonal_decoupled &&
                    (st.use_loc || st.use_givens_mean || st.use_anc || any(st.centered_dims))
    run_raw = if use_decoupled
        r_u = B._run_generalized_candidate_advancedhmc(
            st, initial;
            _initial_transform = x -> from_raw(st, x),
            ndraws,
            warmup,
            chains,
            seed = seed === nothing ? nothing : Int(seed),
            rng,
            target_accept = ta_res,
            max_depth = md_res,
            step_size,
            init_jitter,
            metric,
            ad_backend = resolved_ad,
            progress,
            chain_execution,
            max_parallel_chains,
            rhat_threshold,
            ess_threshold,
            record_warmup = true,
        )
        S_draws = size(r_u.draws, 1)
        q_draws = Matrix{Float64}(undef, S_draws, t.dimension)
        q_logdens = Vector{Float64}(undef, S_draws)
        q_stats = Vector{NamedTuple}(undef, S_draws)
        for s in 1:S_draws
            qs, ljs = _to_raw_with_logjac(st, view(r_u.draws, s, :))
            q_draws[s, :] .= qs
            lp_q = r_u.logdensities[s] - ljs
            q_logdens[s] = lp_q
            q_stats[s] = merge(r_u.sampler_stats[s], (; log_density = lp_q))
        end
        _, lj_init = _to_raw_with_logjac(st, from_raw(st, initial))
        q_srows = B._generalized_candidate_sampler_rows(
            q_logdens, r_u.iterations, r_u.chain_acceptance, q_stats, r_u.controls, r_u.backend)
        merge(r_u, (; draws = q_draws, logdensities = q_logdens, sampler_stats = q_stats,
            sampler_rows = q_srows, initial = initial,
            initial_logdensity = r_u.initial_logdensity - lj_init))
    else
        B._run_generalized_candidate_advancedhmc(
            t, initial;
            ndraws,
            warmup,
            chains,
            seed = seed === nothing ? nothing : Int(seed),
            rng,
            target_accept = ta_res,
            max_depth = md_res,
            step_size,
            init_jitter,
            metric,
            ad_backend = resolved_ad,
            progress,
            chain_execution,
            max_parallel_chains,
            rhat_threshold,
            ess_threshold,
            record_warmup = true,
        )
    end
    t_rec = target_record(t)
    tid = target_identity(t)
    producer = (;
        julia = string(VERSION),
        package = string(Base.pkgversion(B)),
        advancedhmc = string(Base.pkgversion(B.AdvancedHMC)),
        diagnostic_tools = string(Base.pkgversion(B.MCMCDiagnosticTools)),
        sampling_coordinates = use_decoupled ? :orthogonal_decoupled : :raw,
        centered_dims = use_decoupled ? Tuple(st.centered_dims) : Tuple(falses(t.D)),
    )
    body = (; schema = FIT_SCHEMA, target = t_rec, target_identity = tid, run = run_raw, producer)
    f = Fit(merge(body, (; content_hash = B._cache_hash(body))))
    checked(f; full = true)
    return f
end

function _extract_model_vector!(row_out::AbstractVector{Float64}, t::Target, c)
    idx = 0
    @inbounds for p in 1:t.P, d in 1:t.D
        idx += 1
        row_out[idx] = Float64(c.person[p, d])
    end
    @inbounds for d in 1:t.D
        idx += 1
        row_out[idx] = Float64(c.ability_mean[d])
    end
    @inbounds for d in 1:t.D
        idx += 1
        row_out[idx] = Float64(c.ability_sd[d])
    end
    @inbounds for (i, d) in t.active_pairs
        idx += 1
        row_out[idx] = Float64(c.loading[i, d])
    end
    @inbounds for (i, d) in t.active_pairs
        idx += 1
        row_out[idx] = Float64(c.standardized_loading[i, d])
    end
    @inbounds for i in 1:t.I
        idx += 1
        row_out[idx] = Float64(c.item[i])
    end
    @inbounds for r in 1:t.R
        idx += 1
        row_out[idx] = Float64(c.rater[r])
    end
    @inbounds for r in 1:t.R
        idx += 1
        row_out[idx] = Float64(c.consistency[r])
    end
    @inbounds for g in 1:t.n_step_groups, m in 1:t.H
        idx += 1
        row_out[idx] = Float64(c.steps[g, m])
    end
    if t.prior.latent_correlation === :lkj
        for i_d in 2:t.D, j_d in 1:(i_d - 1)
            idx += 1
            row_out[idx] = Float64(c.correlation_matrix[i_d, j_d])
        end
        if t.D == 3
            idx += 1
            row_out[idx] = Float64(c.partial_correlations[3])
        end
    end
    if t.prior.aggregation === :softmin
        idx += 1
        row_out[idx] = Float64(c.softmin_kappa)
    end
    return row_out
end

function model_draws(t::Target, raw::AbstractMatrix{<:Real})
    S = size(raw, 1)
    M = length(t.model_names)
    values = Matrix{Float64}(undef, S, M)
    for s in 1:S
        c = coordinates(t, view(raw, s, :))
        _extract_model_vector!(view(values, s, :), t, c)
    end
    return (; names = copy(t.model_names), values, fixed = copy(t.fixed_model_names))
end

function selected(t::Target, run::NamedTuple; scale::Symbol = :model, parameters = nothing)
    scale in (:raw, :model) || throw(ArgumentError("scale must be :raw or :model"))
    m = scale === :model ? model_draws(t, run.draws) :
        (; names = copy(t.raw_names), values = run.draws, fixed = Set{String}())
    chosen = parameters === nothing ? m.names : String[String(p) for p in parameters]
    !isempty(chosen) && allunique(chosen) && all(n -> n in m.names, chosen) ||
        throw(ArgumentError("select distinct parameter_names from scale = $(repr(scale))"))
    ix = [only(findall(==(n), m.names)) for n in chosen]
    return (; names = chosen, values = m.values[:, ix], fixed = m.fixed)
end

function weighted_sufficient_score(f::Fit; dimension::Int = 1, interval::Real = 0.95)
    t = checked(f)
    1 <= dimension <= t.D || throw(ArgumentError("dimension must be in 1:$(t.D)"))
    lo, hi = _interval_bounds(interval)
    draws = f.record.run.draws
    S = size(draws, 1)
    chains = f.record.run.controls.chains
    P = t.P

    obs_by_p = [Int[] for _ in 1:P]
    for n in 1:t.N
        if dimension in t.active_dims_of_item[t.item[n]]
            push!(obs_by_p[t.person[n]], n)
        end
    end

    w_sum_draws = zeros(Float64, S, P)
    w_mean_draws = fill(NaN, S, P)
    for s in 1:S
        c = coordinates(t, view(draws, s, :))
        @inbounds for p in 1:P
            ns = obs_by_p[p]
            isempty(ns) && continue
            ws_num = 0.0
            ws_cat = 0.0
            w_tot = 0.0
            for n in ns
                i = t.item[n]
                r = t.rater[n]
                y_0 = Float64(t.category[n] - 1)
                x_val = Float64(t.category_levels[t.category[n]])
                w_n = Float64(c.consistency[r]) * Float64(c.loading[i, dimension])
                ws_cat += w_n * y_0
                ws_num += w_n * x_val
                w_tot += w_n
            end
            w_sum_draws[s, p] = ws_cat
            w_mean_draws[s, p] = w_tot > 0.0 ? (ws_num / w_tot) : NaN
        end
    end

    rows = map(1:P) do p
        ns = obs_by_p[p]
        m_p = length(ns)
        raw_s = sum((Float64(t.category_levels[t.category[n]]) for n in ns); init = 0.0)
        raw_m = m_p > 0 ? raw_s / m_p : NaN
        v_ws = view(w_sum_draws, :, p)
        v_wm = view(w_mean_draws, :, p)
        wm_mcse = (m_p > 0 && all(isfinite, v_wm)) ?
            B.MCMCDiagnosticTools.mcse(reshape(v_wm, div(S, chains), chains)) : NaN
        (;
            person = t.person_levels[p],
            dimension,
            n_ratings = m_p,
            raw_sum = raw_s,
            raw_mean = raw_m,
            weighted_sufficient_mean = mean(v_ws),
            weighted_sufficient_sd = std(v_ws),
            weighted_sufficient_lower = quantile(v_ws, lo),
            weighted_sufficient_upper = quantile(v_ws, hi),
            weighted_average_mean = m_p > 0 ? mean(v_wm) : NaN,
            weighted_average_sd = m_p > 0 ? std(v_wm) : NaN,
            weighted_average_lower = m_p > 0 ? quantile(v_wm, lo) : NaN,
            weighted_average_upper = m_p > 0 ? quantile(v_wm, hi) : NaN,
            weighted_average_mcse = wm_mcse,
            adjustment_vs_raw_mean = m_p > 0 ? (mean(v_wm) - raw_m) : NaN,
        )
    end

    return (;
        schema = WEIGHTED_SCORE_SCHEMA,
        kind = :weighted_sufficient_score,
        family = t.prior.family_tag,
        dimension,
        interval = Float64(interval),
        n_persons = P,
        n_draws = S,
        rows,
        qualification = qualify(f),
        source_sample_content_hash = f.record.content_hash,
    )
end

function diagnostics(f::Fit; kind::Symbol = :mcmc, kwargs...)
    if kind === :weighted_sufficient_score
        return weighted_sufficient_score(f; kwargs...)
    elseif kind !== :mcmc
        throw(ArgumentError("ScaleIdentifiedMGMFRM.diagnostics supports kind = :mcmc or :weighted_sufficient_score; got $(repr(kind))"))
    end
    isempty(kwargs) || throw(ArgumentError("diagnostics(fit; kind = :mcmc) takes no extra keyword arguments"))
    t = checked(f)
    run = f.record.run
    m = model_draws(t, run.draws)
    raw_space = _is_v1_compatible_prior(t.prior) ? :white : :parameter_specific
    diagnose(x, n; space, fixed = Set{String}()) = B._candidate_mcmc_diagnostic_rows(
        x, n, run.controls.chains;
        parameter_space = space,
        structurally_fixed_parameters = fixed,
        split_chains = run.split_chains_requested,
        rhat_threshold = run.checked.rhat_threshold,
        ess_threshold = run.checked.ess_threshold,
    )
    return (;
        raw = diagnose(run.draws, t.raw_names; space = raw_space),
        model = diagnose(m.values, m.names; space = :model, fixed = m.fixed),
        sampler = deepcopy(run.sampler_rows),
        warmup = B._warmup_diagnostic_rows(run.warmup_stats, run.controls, run.backend),
        thresholds = (; run.checked..., minimum_chains = 2),
        scientific_acceptance = false,
    )
end

function qualify(f::Fit;
        max_rhat::Real = 1.01,
        min_ess::Real = 400.0,
        min_bfmi::Union{Nothing, Real} = nothing,
        ebfmi_min::Union{Nothing, Real} = nothing,
        bfmi_min::Union{Nothing, Real} = nothing)
    min_ess isa Bool && throw(ArgumentError("min_ess must be a finite positive real number"))
    thresholds = B._check_diagnostic_thresholds(max_rhat, min_ess)
    resolved_bfmi = B._resolve_bfmi_alias(;
        min_bfmi, ebfmi_min, bfmi_min, default_min_bfmi = 0.30, caller = "qualify")
    return B._qualify_experimental_diagnostics(diagnostics(f), f.record.run, thresholds, Float64(resolved_bfmi))
end

function _interval_bounds(interval)
    interval isa Real && !(interval isa Bool) && isfinite(interval) && 0.0 < interval < 1.0 ||
        throw(ArgumentError("interval must be in (0, 1)"))
    lo = (1.0 - Float64(interval)) / 2.0
    return (lo, 1.0 - lo)
end

function summary(f::Fit; scale::Symbol = :model, parameters = nothing, interval::Real = 0.95)
    t = checked(f)
    m = selected(t, f.record.run; scale, parameters)
    lo, hi = _interval_bounds(interval)
    rows = B._posterior_summary_rows(
        m.values, m.names;
        lower = lo, upper = hi, intervals = (Float64(interval),),
        reference = 0.0, rope = nothing, rope_probability_threshold = 0.95,
    )
    return (;
        scale,
        logit_scale = t.prior.logit_scale,
        scale_identification = t.prior.scale_identification,
        location_identification = t.prior.location_identification,
        interval = Float64(interval),
        rows = [(;
            r.parameter,
            r.mean,
            r.sd,
            r.median,
            r.lower,
            r.upper,
            structurally_fixed = r.parameter in m.fixed,
        ) for r in rows],
        source_sample_content_hash = f.record.content_hash,
        scientific_acceptance = false,
    )
end

function mcse(f::Fit; scale::Symbol = :model, parameters = nothing, probabilities = (0.025, 0.5, 0.975))
    t = checked(f)
    m = selected(t, f.record.run; scale, parameters)
    return B._posterior_mcse_rows(
        m.values, m.names, f.record.run.controls.chains;
        probabilities,
        parameter_space = scale,
        structurally_fixed_parameters = m.fixed,
    )
end

function contrast(f::Fit;
        facet::Union{Nothing, Symbol} = nothing,
        left,
        right,
        dimension::Int = 1,
        interval::Union{Nothing, Real} = nothing,
        level::Union{Nothing, Real} = nothing,
        rope = nothing)
    (interval !== nothing && level !== nothing) &&
        throw(ArgumentError("supply either `interval` or `level` to contrast, not both"))
    iv = Float64(something(interval, level, 0.95))
    t = checked(f)
    lname, rname = if facet === nothing
        l_s, r_s = String(left), String(right)
        l_s != r_s || throw(ArgumentError("left and right must be distinct parameter names"))
        (l_s, r_s)
    else
        blk = facet === :entity ? :person : (facet === :criterion ? :item : facet)
        if blk === :person
            1 <= dimension <= t.D || throw(ArgumentError("dimension must be in 1:$(t.D)"))
            ll = t.person_levels[B.AdditiveFacets._resolve_facet_level !== nothing ?
                findfirst(isequal(B.AdditiveFacets._resolve_facet_level(t.person_levels, left, :person)), t.person_levels) : 1]
            rl = t.person_levels[findfirst(isequal(B.AdditiveFacets._resolve_facet_level(t.person_levels, right, :person)), t.person_levels)]
            isequal(ll, rl) && throw(ArgumentError("choose distinct person levels for contrast"))
            ("person[$(_fmt_label(ll)), dim=$dimension]", "person[$(_fmt_label(rl)), dim=$dimension]")
        elseif blk in (:item, :rater, :consistency)
            levs = blk === :item ? t.item_levels : t.rater_levels
            ll = B.AdditiveFacets._resolve_facet_level(levs, left, blk)
            rl = B.AdditiveFacets._resolve_facet_level(levs, right, blk)
            isequal(ll, rl) && throw(ArgumentError("choose distinct $blk levels for contrast"))
            ("$(blk)[$(_fmt_label(ll))]", "$(blk)[$(_fmt_label(rl))]")
        elseif blk in (:loading, :standardized_loading)
            1 <= dimension <= t.D || throw(ArgumentError("dimension must be in 1:$(t.D)"))
            ll = B.AdditiveFacets._resolve_facet_level(t.item_levels, left, :item)
            rl = B.AdditiveFacets._resolve_facet_level(t.item_levels, right, :item)
            isequal(ll, rl) && throw(ArgumentError("choose distinct items for $blk contrast"))
            ("$(blk)[$(_fmt_label(ll)), dim=$dimension]", "$(blk)[$(_fmt_label(rl)), dim=$dimension]")
        else
            throw(ArgumentError(
                "unsupported facet $(repr(facet)); use :person, :item, :criterion, :rater, :consistency, :loading, :standardized_loading, or supply full parameter names with facet = nothing"))
        end
    end
    m = selected(t, f.record.run; scale = :model, parameters = [lname, rname])
    res = B.posterior_contrast(
        view(m.values, :, 1), view(m.values, :, 2);
        chains = f.record.run.controls.chains, interval = iv, rope,
    )
    p_row = only(filter(e -> e.event == "above_zero", res.event_rows))
    return (;
        facet,
        left = lname,
        right = rname,
        level = iv,
        interval = iv,
        mean = res.mean,
        sd = res.sd,
        median = res.median,
        lower = res.lower,
        upper = res.upper,
        eti = (res.lower, res.upper),
        prob_positive = p_row.probability,
        prob_positive_mcse = p_row.mean_mcse,
        mean_mcse = res.precision.mean_mcse,
        lower_mcse = res.precision.quantiles[1].mcse,
        upper_mcse = res.precision.quantiles[3].mcse,
        result = res,
        qualification = qualify(f),
        source_sample_content_hash = f.record.content_hash,
        scientific_acceptance = false,
    )
end

function pointwise_loglikelihood_matrix(f::Fit)
    t = checked(f)
    draws = f.record.run.draws
    S = size(draws, 1)
    ll = Matrix{Float64}(undef, S, t.N)
    B._parallel_ranges(S, t.N) do indices
        for s in indices
            ll[s, :] .= pointwise_loglikelihood(t, view(draws, s, :))
        end
    end
    return ll
end

function predict(f::Fit; rows = nothing, interval::Real = 0.95)
    t = checked(f)
    ix = rows === nothing ? collect(1:t.N) : Int[Int(r) for r in rows]
    !isempty(ix) && all(r -> 1 <= r <= t.N, ix) ||
        throw(ArgumentError("rows must be nonempty integer indices in 1:$(t.N)"))
    lo, hi = _interval_bounds(interval)
    draws = f.record.run.draws
    S = size(draws, 1)
    K = t.K
    n_sel = length(ix)
    prob_cube = Array{Float64}(undef, S, n_sel, K)
    logits = Vector{Float64}(undef, K)

    for s in 1:S
        c = coordinates(t, view(draws, s, :))
        @inbounds for (j, n) in enumerate(ix)
            p, i, r = t.person[n], t.item[n], t.rater[n]
            g = t.step_group_of_obs[n]
            loc_z, alpha_z = _obs_loc_and_scale(t, c, p, i, r)
            loc = Float64(loc_z)
            alpha_obs = Float64(alpha_z)
            logits[1] = 0.0
            mx = 0.0
            for k in 2:K
                lk = logits[k - 1] + alpha_obs * (loc - c.steps[g, k - 1])
                logits[k] = lk
                lk > mx && (mx = lk)
            end
            denom = 0.0
            for k in 1:K
                w = exp(logits[k] - mx)
                prob_cube[s, j, k] = w
                denom += w
            end
            inv_d = 1.0 / denom
            for k in 1:K
                prob_cube[s, j, k] *= inv_d
            end
        end
    end

    means = zeros(Float64, n_sel, K)
    lower = zeros(Float64, n_sel, K)
    upper = zeros(Float64, n_sel, K)
    for j in 1:n_sel, k in 1:K
        v = view(prob_cube, :, j, k)
        means[j, k] = mean(v)
        lower[j, k] = quantile(v, lo)
        upper[j, k] = quantile(v, hi)
    end
    cells = [
        (;
            position = j,
            row = ix[j],
            category = t.category_levels[k],
            mean = means[j, k],
            lower = lower[j, k],
            upper = upper[j, k],
        ) for j in 1:n_sel for k in 1:K
    ]
    return (;
        schema = PREDICTION_SCHEMA,
        rows = ix,
        category_levels = copy(t.category_levels),
        interval = Float64(interval),
        mean = means,
        lower,
        upper,
        cells,
        qualification = qualify(f),
        target_identity = f.record.target_identity,
        source_sample_content_hash = f.record.content_hash,
        scientific_acceptance = false,
    )
end

function posterior_predictive_check(f::Fit;
        seed::Integer = 1,
        ndraws::Union{Nothing, Int} = nothing,
        interval::Real = 0.95,
        rng::Union{Nothing, AbstractRNG} = nothing)
    seed isa Integer && !(seed isa Bool) || throw(ArgumentError("seed must be an integer"))
    t = checked(f)
    lo, hi = _interval_bounds(interval)
    draws = f.record.run.draws
    S_tot = size(draws, 1)
    n_rep = ndraws === nothing ? S_tot : ndraws
    1 <= n_rep <= S_tot || throw(ArgumentError("ndraws must be in 1:$S_tot"))
    actual_rng = rng === nothing ? Random.MersenneTwister(Int(seed)) : rng

    rep_props = Matrix{Float64}(undef, n_rep, t.K)
    rep_item_means = Matrix{Float64}(undef, n_rep, t.I)
    item_counts = [count(==(i), t.item) for i in 1:t.I]

    for s in 1:n_rep
        c = coordinates(t, view(draws, s, :))
        probs = _category_probs_point(t, c)
        cat_counts = zeros(Int, t.K)
        item_sums = zeros(Float64, t.I)
        @inbounds for n in 1:t.N
            u = rand(actual_rng)
            cum = 0.0
            chosen = t.K
            for k in 1:t.K
                cum += probs[n, k]
                if u <= cum
                    chosen = k
                    break
                end
            end
            cat_counts[chosen] += 1
            item_sums[t.item[n]] += t.category_levels[chosen]
        end
        for k in 1:t.K
            rep_props[s, k] = cat_counts[k] / t.N
        end
        for i in 1:t.I
            rep_item_means[s, i] = item_counts[i] > 0 ? item_sums[i] / item_counts[i] : NaN
        end
    end

    obs_props = [count(==(k), t.category) / t.N for k in 1:t.K]
    obs_item_means = [mean(t.category_levels[t.category[n]] for n in 1:t.N if t.item[n] == i) for i in 1:t.I]
    category_rows = [
        (;
            category = t.category_levels[k],
            observed = obs_props[k],
            mean = mean(view(rep_props, :, k)),
            lower = quantile(view(rep_props, :, k), lo),
            upper = quantile(view(rep_props, :, k), hi),
        ) for k in 1:t.K
    ]
    item_rows = [
        (;
            item = t.item_levels[i],
            observed_mean = obs_item_means[i],
            replicated_mean = mean(view(rep_item_means, :, i)),
            lower = quantile(view(rep_item_means, :, i), lo),
            upper = quantile(view(rep_item_means, :, i), hi),
        ) for i in 1:t.I
    ]
    return (;
        schema = PPC_SCHEMA,
        seed = Int(seed),
        n_replications = n_rep,
        interval = Float64(interval),
        category_rows,
        item_rows,
        qualification = qualify(f),
        target_identity = f.record.target_identity,
        source_sample_content_hash = f.record.content_hash,
        scientific_acceptance = false,
    )
end

function _trace_payload(t::Target, run::NamedTuple; scale::Symbol = :model, parameters = nothing)
    m = selected(t, run; scale, parameters)
    nch = run.controls.chains
    per_ch = run.controls.ndraws
    series = [
        (;
            parameter = nm,
            chain = c,
            iterations = collect(1:per_ch),
            values = Float64[m.values[(c - 1) * per_ch + s, j] for s in 1:per_ch],
        ) for (j, nm) in enumerate(m.names) for c in 1:nch
    ]
    return (; scale, chains = nch, draws_per_chain = per_ch, parameters = copy(m.names), series)
end

function report(f::Fit; scale::Symbol = :model, parameters = nothing, interval::Real = 0.95, include_draws::Bool = false)
    t = checked(f)
    lo, hi = _interval_bounds(interval)
    base = (;
        schema = REPORT_SCHEMA,
        contract = contract(t),
        summary = summary(f; scale, parameters, interval),
        mcse = mcse(f; scale, parameters, probabilities = (lo, 0.5, hi)),
        qualification = qualify(f),
        controls = deepcopy(f.record.run.controls),
        producer = f.record.producer,
        target_identity = f.record.target_identity,
        source_sample_content_hash = f.record.content_hash,
        scientific_acceptance = false,
    )
    return include_draws ? merge(base, (; traces = _trace_payload(t, f.record.run; scale, parameters))) : base
end

function save_result(path::AbstractString, f::Fit)
    checked(f; full = true)
    return B._save_serialized_record(path, f; overwrite = false)
end

function load_result(f::Fit)
    checked(f; full = true)
    return f
end

function _jsonsafe_report(rep)
    if hasproperty(rep, :contract) && hasproperty(rep.contract, :anchor_items) && rep.contract.anchor_items !== nothing
        anc = [_fmt_label(x) for x in rep.contract.anchor_items]
        rep = merge(rep, (; contract = merge(rep.contract, (; anchor_items = anc))))
    end
    return B.Experimental.JointRatings.W.jsonsafe(rep)
end

function save_computed(path::AbstractString, rep)
    check_loaded_report(rep)
    (ispath(path) || islink(path)) && throw(ArgumentError("report already exists: $path"))
    mkpath(dirname(path))
    mktemp(dirname(path)) do temporary, io
        B.JSON3.write(io, _jsonsafe_report(rep))
        close(io)
        hardlink(temporary, path)
    end
    return path
end

function check_loaded_report(parsed)
    hasproperty(parsed, :schema) && String(parsed.schema) in REPORT_SCHEMAS ||
        throw(ArgumentError("unsupported scale-identified MGMFRM report schema"))
    hasproperty(parsed, :source_sample_content_hash) ||
        throw(ArgumentError("scale-identified MGMFRM report is missing source_sample_content_hash"))
    return parsed
end

end # module ScaleIdentifiedMGMFRM
