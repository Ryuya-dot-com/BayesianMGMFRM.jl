"""
Non-Bayesian frequentist 1D Rating Scale Model (RSM) and Partial Credit Model (PCM)
estimation via Joint Maximum Likelihood (`JMLE`) and Marginal Maximum Likelihood (`MMLE`).

Supports both standard 3-facet `FacetSpec` / `FacetDesign` (`person`, `rater`, `item`)
and general user-named F-facet `mfrm_spec` (`AdditiveFacets.Target`, pure-facet
`AdditiveFacets.ExplanatoryTarget`, and prior-free `FrequentistMFRM.Spec`), with:
- Exact sum-to-zero (`:sum_to_zero`, default, aligned with `mfrmr 0.3.0`, `mfrmpy 0.2.0`,
  `FACETS`, and `ConQuest`) or first-level reference (`:reference_first`, aligned with
  `BayesianMGMFRM.FacetDesign`) identification gauges and exact hard anchors;
- Exact unadjusted JMLE (separating unbounded extreme persons to +/-Inf while preserving
  the exact interior supremum, plus optional FACETS-style `extreme_adjustment` e.g. `0.3`);
- Gauss-Hermite (`:gauss_hermite`, Golub-Welsch) or normal-density rectangular
  (`:rectangular`) quadrature MMLE under fixed `N(0, population_sd^2)` (default),
  ConQuest-compatible free-SD `N(0, sigma^2)` (`estimate_sd = true`), or full normal
  `N(mu, sigma^2)` (`estimate_sd = true, estimate_mean = true`);
- Exact constrained observed-information Hessian SEs (`se`, via block Schur complement in
  JMLE and exact marginal-log-likelihood Hessian in MMLE) alongside FACETS-compatible
  conditional/diagonal SEs (`conditional_se`, `ModelSE`) and `real_se` (`RealSE`);
- `EAP` (quadrature posterior mean/SD/quantiles), Warm `WLE`, and fixed-calibration `MLE`
  person scoring;
- Wright & Masters (1982, Eq. 4.27) FACETS degrees of freedom and Wilson-Hilferty cube-root
  `Infit` / `Outfit` `MNSQ` and `ZSTD` alongside homogeneous-variance engine sidecars,
  point-measure correlations (`ptmea`), and facet separation/reliability summaries.

All outputs explicitly distinguish frequentist point/Wald estimates and empirical-Bayes
quadrature person summaries from full joint Bayesian MCMC posteriors.
"""
module FrequentistMFRM

import BayesianMGMFRM as B
using LinearAlgebra
using SparseArrays
using Statistics
using ForwardDiff
using Distributions
using Serialization
using JSON3
using SHA

const FIT_SCHEMA = "bayesianmgmfrm.frequentist_mfrm_fit.v1"
const REPORT_SCHEMA = "bayesianmgmfrm.frequentist_mfrm_report.v1"
const COMPARISON_SCHEMA = "bayesianmgmfrm.frequentist_mfrm_comparison.v1"

"""
Prior-free 1D additive MFRM specification returned by `mfrm_spec` with
`prior = :none`. Accepted by `fit(spec; method = :jmle | :mmle, ...)` and
design-inspection verbs (`design_summary`, `validate_design`, `contract`, `getdesign`).
"""
struct Spec <: B.AbstractMFRMSpec
    table::Dict{Symbol,Vector}
    columns::NamedTuple
    person::Vector{Int}
    people::Vector{Any}
    category::Vector{Int}
    categories::Vector{Int}
    supports::Vector{UnitRange{Int}}
    facets::Vector{NamedTuple}
    owner::Symbol
    group::Vector{Int}
    group_levels::Vector{Any}
    allocation::NamedTuple
end

function build_spec(table; person::Symbol = :person, score::Symbol = :score, facets::NamedTuple, steps::Symbol = :global,
        category_levels, levels = nothing,
        performance::Union{Nothing,Symbol} = nothing, assessment::Union{Nothing,Symbol} = nothing,
        missing_audit = nothing)
    AF = B.AdditiveFacets
    reserved = (:person, :steps, :global, :score, :performance, :assessment)
    all(k -> !(k in reserved), keys(facets)) ||
        throw(ArgumentError("facet names cannot use reserved roles $reserved"))
    all(x -> x isa Symbol, values(facets)) ||
        throw(ArgumentError("facet mapping values must be column symbols"))
    steps === :global || steps in keys(facets) ||
        throw(ArgumentError("steps must be :global or a declared facet name"))
    selected = Symbol[person, score, values(facets)...]
    performance !== nothing && !(performance in values(facets)) && push!(selected, performance)
    assessment !== nothing && push!(selected, assessment)
    length(unique(selected)) == length(selected) ||
        throw(ArgumentError("each selected role must use a distinct column"))
    raw = Dict{Symbol,Vector}(c => deepcopy(B._column(table, c)) for c in selected)
    n = length(raw[score])
    n > 0 || throw(ArgumentError("ratings cannot be empty"))
    for (c, x) in raw
        B._check_length!(n, x, c)
        c == score || AF._labels(x, c)
    end
    if levels !== nothing
        AF._keys(levels, (:person, :facets), :levels)
        AF._keys(levels.facets, keys(facets), :facet_levels)
    end
    p, ps = AF._labels(raw[person], :person, levels === nothing ? nothing : levels.person)
    fblocks = NamedTuple[]
    af_blocks = AF.Block[]
    offset = length(ps)
    for (name, c) in pairs(facets)
        index, lev = AF._labels(raw[c], name, levels === nothing ? nothing : levels.facets[name])
        m = length(lev)
        push!(fblocks, (; name, column = c, levels = lev, index))
        push!(af_blocks, AF.Block(name, c, lev, index, 1.0, m > 1 ? sqrt(m / (m - 1)) : 0.0, (offset + 1):(offset + m - 1)))
        offset += m - 1
    end
    owner_blk = steps === :global ? nothing : only(filter(b -> b.name === steps, fblocks))
    group = owner_blk === nothing ? ones(Int, n) : copy(owner_blk.index)
    groups = owner_blk === nothing ? Any[:global] : deepcopy(owner_blk.levels)
    cat, categories, supports = AF._category_support(raw[score], score, category_levels, steps, group, groups)
    ranges = AF._step_ranges(supports, offset)
    dim = last(last(ranges))
    alloc = AF._allocation(p, ps, af_blocks, group, supports, dim)
    columns = (; person, score, facets, performance, assessment,
        (missing_audit === nothing ? (;) : (; missing_audit = deepcopy(missing_audit)))...)
    return Spec(raw, columns, p, ps, cat, categories, supports, fblocks, steps, group, groups, alloc)
end

struct FacetDef
    name::Symbol
    levels::Vector{Any}
    index::Vector{Int}
    sign::Int
    anchors::Vector{Float64}
    centered::Bool
    centering::Symbol
end

struct Problem
    source_kind::Symbol
    model::Symbol # :rsm or :pcm
    method::Symbol # :jmle or :mmle
    n_obs::Int
    person_levels::Vector{Any}
    person_idx::Vector{Int}
    person_anchors::Vector{Float64}
    person_centered::Bool
    person_centering::Symbol
    facets::Vector{FacetDef}
    step_owner::Symbol
    step_group::Vector{Int}
    step_group_levels::Vector{Any}
    supports::Vector{UnitRange{Int}}
    score_k::Vector{Int} # 0-based within row's support
    raw_score::Vector{Int}
    weights::Vector{Float64}
    noncenter_facet::Symbol
    centering::Symbol
    observation_binding::String
end

struct Layout
    # Full vector order:
    # [person (1:P) if JMLE else empty; facet_1 (1:L_1); ...; facet_F (1:L_F); steps_1 (1:H_1); ...; steps_G (1:H_G); (mu_theta if MMLE; sigma_theta if MMLE)]
    # Free vector order:
    # [person_free (1:d_theta) if JMLE; structural_free (1:d_psi); (mu_free; log_sigma_free)]
    n_full_structural::Int
    person_full_range::UnitRange{Int}
    facet_full_ranges::Vector{UnitRange{Int}}
    step_full_ranges::Vector{UnitRange{Int}}
    person_free_range::UnitRange{Int}
    facet_free_ranges::Vector{UnitRange{Int}}
    step_free_ranges::Vector{UnitRange{Int}}
    mu_free_idx::Int
    log_sigma_free_idx::Int
    n_free::Int
    c_vec::Vector{Float64}
    J_mat::SparseMatrixCSC{Float64,Int}
    free_names::Vector{String}
    full_names::Vector{String}
    fixed_mask::BitVector
    extreme_person_status::Vector{Symbol} # :interior, :all_minimum, :all_maximum, :anchored, :unobserved
    interior_persons::Vector{Int}
    active_rows::Vector{Int}
end

struct Fit <: B.AbstractMFRMFit
    record::NamedTuple
end

function Base.show(io::IO, f::Fit)
    s = f.record.summary
    print(io, "FrequentistMFRM.Fit(method = :", s.method,
        ", model = :", s.model,
        ", n_obs = ", s.n_observations,
        ", n_persons = ", s.n_persons,
        ", loglik = ", round(s.loglikelihood; digits = 4),
        ", converged = ", s.converged, ")")
end

# ---------------------------------------------------------------------------
# 1. Quadrature Rules (Golub-Welsch Gauss-Hermite & Normal Rectangular Grid)
# ---------------------------------------------------------------------------

function gauss_hermite_normal(n::Int; sd::Real = 1.0)
    n >= 1 || throw(ArgumentError("quad_points must be an integer >= 1"))
    s = Float64(sd)
    isfinite(s) && s > 0.0 || throw(ArgumentError("population_sd must be finite and positive"))
    if n == 1
        return (; nodes = [0.0], std_nodes = [0.0], weights = [1.0], sd = s, rule = :gauss_hermite)
    end
    off = [sqrt(Float64(j)) for j in 1:(n - 1)]
    eig = eigen(SymTridiagonal(zeros(Float64, n), off))
    std_nodes = Vector{Float64}(eig.values)
    weights = vec(eig.vectors[1, :] .^ 2)
    weights ./= sum(weights)
    nodes = std_nodes .* s
    all(isfinite, nodes) || throw(ArgumentError("quadrature nodes overflowed"))
    return (; nodes, std_nodes, weights, sd = s, rule = :gauss_hermite)
end

function rectangular_normal(n::Int; sd::Real = 1.0, theta_lim::Real = 4.0)
    n >= 3 || throw(ArgumentError("rectangular quadrature requires quad_points >= 3"))
    s = Float64(sd)
    lim = Float64(theta_lim)
    isfinite(s) && s > 0.0 && isfinite(lim) && lim > 0.0 ||
        throw(ArgumentError("population_sd and theta_lim must be finite and positive"))
    std_nodes = collect(range(-lim, lim; length = n))
    raw_w = [exp(-0.5 * z^2) for z in std_nodes]
    weights = raw_w ./ sum(raw_w)
    return (; nodes = std_nodes .* s, std_nodes, weights, sd = s, rule = :rectangular)
end

function build_quadrature(rule::Symbol, n::Int; sd::Real = 1.0, theta_lim::Real = 4.0)
    rule === :gauss_hermite && return gauss_hermite_normal(n; sd)
    rule === :rectangular && return rectangular_normal(n; sd, theta_lim)
    throw(ArgumentError("quadrature must be :gauss_hermite or :rectangular; got $(repr(rule))"))
end

# ---------------------------------------------------------------------------
# 2. Input Normalization & Problem Compilation
# ---------------------------------------------------------------------------

function _normalize_method(method::Symbol)
    method in (:jmle, :jml) && return :jmle
    method in (:mmle, :mml) && return :mmle
    throw(ArgumentError("frequentist method must be :jmle (:jml) or :mmle (:mml); got $(repr(method))"))
end

function _observation_binding_hash(person_levels, person_idx, facets::Vector{FacetDef}, supports, step_group, raw_score, weights)
    row_supports = [(first(supports[step_group[i]]), last(supports[step_group[i]])) for i in eachindex(raw_score)]
    payload = (;
        person = [string(person_levels[p]) for p in person_idx],
        facets = [(; name = String(f.name), values = [string(f.levels[i]) for i in f.index]) for f in facets],
        row_supports,
        raw_score,
        weights,
    )
    return B._cache_hash(payload)
end

function _parse_anchor_vector(levels::Vector{Any}, anchor_map)
    out = fill(NaN, length(levels))
    anchor_map === nothing && return out
    pairs_iter = anchor_map isa AbstractDict ? pairs(anchor_map) :
                 anchor_map isa NamedTuple ? pairs(anchor_map) :
                 throw(ArgumentError("facet anchors must be a Dict or NamedTuple mapping level => value"))
    for (k, v) in pairs_iter
        v isa Real && !(v isa Bool) && isfinite(v) ||
            throw(ArgumentError("anchor value for $(repr(k)) must be a finite real number"))
        idx = findfirst(l -> isequal(l, k) || string(l) == string(k), levels)
        idx === nothing && throw(ArgumentError("anchor level $(repr(k)) is not in declared levels"))
        out[idx] = Float64(v)
    end
    return out
end

function compile_problem(spec::B.FacetSpec;
        method::Symbol,
        noncenter_facet::Symbol = :person,
        centering::Symbol = :sum_to_zero,
        positive_facets = Symbol[],
        anchors = NamedTuple(),
        weights = nothing)
    m = _normalize_method(method)
    spec.family === :mfrm ||
        throw(ArgumentError("frequentist JMLE/MMLE supports 1D RSM/PCM (family = :mfrm); got family = $(repr(spec.family))"))
    spec.dimensions == 1 ||
        throw(ArgumentError("frequentist JMLE/MMLE supports 1D models only; got dimensions = $(spec.dimensions)"))
    spec.discrimination === :none ||
        throw(ArgumentError("frequentist JMLE/MMLE supports unit-slope RSM/PCM only (discrimination = :none); GPCM is out of scope"))
    spec.thresholds in (:rating_scale, :partial_credit) ||
        throw(ArgumentError("frequentist JMLE/MMLE requires thresholds = :rating_scale or :partial_credit"))
    isempty(spec.validation_bias_terms) ||
        throw(ArgumentError("frequentist JMLE/MMLE does not fit bias/interaction terms directly"))
    spec.validation.passed ||
        throw(ArgumentError("FacetSpec failed design validation; inspect validate_design(spec) before fitting"))
    centering in (:sum_to_zero, :reference_first) ||
        throw(ArgumentError("centering must be :sum_to_zero or :reference_first"))

    d = spec.data
    n = d.n
    w = weights === nothing ? ones(Float64, n) : Float64.(weights)
    length(w) == n && all(x -> isfinite(x) && x > 0.0, w) ||
        throw(ArgumentError("weights must have length $n with finite positive values"))

    pos_set = Set{Symbol}(Symbol.(collect(positive_facets)))
    # Merge spec.anchors (Vector{NamedTuple}) with explicit keyword anchors (Dict/NamedTuple)
    merged_anchors = Dict{Symbol,Dict{Any,Float64}}()
    for anchor in spec.anchors
        anchor.anchor_type === :hard_anchor ||
            throw(ArgumentError("frequentist JMLE/MMLE supports hard equality anchors only; got $(repr(anchor.anchor_type))"))
        blk = anchor.block in (:rater, :rater_severity, :raters) ? :rater :
              anchor.block in (:item, :item_difficulty, :items) ? :item :
              anchor.block in (:person, :person_ability, :persons) ? :person :
              throw(ArgumentError("unsupported FacetSpec anchor block $(repr(anchor.block)) for frequentist MFRM"))
        tgt = B._anchor_target(anchor)
        ismissing(tgt) && throw(ArgumentError("FacetSpec anchor for $(repr(blk)) is missing its target level"))
        dmap = get!(merged_anchors, blk, Dict{Any,Float64}())
        dmap[tgt] = Float64(anchor.value)
    end
    for (facet_sym, fdict) in pairs(anchors)
        dmap = get!(merged_anchors, Symbol(facet_sym), Dict{Any,Float64}())
        for (lvl, val) in pairs(fdict)
            dmap[lvl] = Float64(val)
        end
    end

    p_anchors = _parse_anchor_vector(Vector{Any}(d.person_levels), get(merged_anchors, :person, nothing))
    if m === :mmle && any(isfinite, p_anchors)
        throw(ArgumentError("MMLE integrates person abilities over the population distribution and does not accept person anchors; use method = :jmle for fixed person anchors"))
    end
    allowed_facets = (:person, :rater, :item)
    noncenter_facet in allowed_facets ||
        throw(ArgumentError("noncenter_facet must be one of $allowed_facets; got $(repr(noncenter_facet))"))
    all(f -> f in allowed_facets, pos_set) ||
        throw(ArgumentError("positive_facets entries must belong to $allowed_facets"))

    fdefs = FacetDef[]
    for (fname, flevels, fidx) in (
        (:rater, Vector{Any}(d.rater_levels), copy(d.rater)),
        (:item, Vector{Any}(d.item_levels), copy(d.item)),
    )
        fanc = _parse_anchor_vector(flevels, get(merged_anchors, fname, nothing))
        has_anc = any(isfinite, fanc)
        is_cent = !has_anc && (m === :mmle ? fname !== noncenter_facet || noncenter_facet === :person : fname !== noncenter_facet)
        sgn = fname in pos_set ? 1 : -1
        push!(fdefs, FacetDef(fname, flevels, fidx, sgn, fanc, is_cent, centering))
    end

    p_has_anc = any(isfinite, p_anchors)
    p_cent = m === :jmle && !p_has_anc && noncenter_facet !== :person

    is_rsm = spec.thresholds === :rating_scale
    step_owner = is_rsm ? :global : :item
    step_group = is_rsm ? ones(Int, n) : copy(d.item)
    step_group_levels = is_rsm ? Any[:global] : Vector{Any}(d.item_levels)
    cat_range = first(d.category_levels):last(d.category_levels)
    collect(cat_range) == d.category_levels ||
        throw(ArgumentError("frequentist RSM/PCM requires consecutive integer category_levels"))
    supports = [cat_range for _ in eachindex(step_group_levels)]
    score_k = d.category .- 1
    raw_score = [d.category_levels[c] for c in d.category]
    obs_bind = _observation_binding_hash(d.person_levels, d.person, fdefs, supports, step_group, raw_score, w)
    return Problem(
        :facet_spec, is_rsm ? :rsm : :pcm, m, n,
        Vector{Any}(d.person_levels), copy(d.person), p_anchors, p_cent, centering,
        fdefs, step_owner, step_group, step_group_levels, supports,
        score_k, raw_score, w, noncenter_facet, centering, obs_bind,
    )
end

compile_problem(design::B.FacetDesign; kwargs...) = compile_problem(design.spec; kwargs...)

function _compile_additive_common(source_kind::Symbol, person_levels::Vector{Any}, person_idx::Vector{Int},
        facet_tuples::AbstractVector{<:NamedTuple}, step_owner::Symbol, step_group::Vector{Int},
        step_group_levels::Vector{Any}, supports::Vector{UnitRange{Int}}, raw_cat::Vector{Int};
        method::Symbol,
        noncenter_facet::Symbol = :person,
        centering::Symbol = :sum_to_zero,
        positive_facets = Symbol[],
        anchors = NamedTuple(),
        weights = nothing)
    m = _normalize_method(method)
    centering in (:sum_to_zero, :reference_first) ||
        throw(ArgumentError("centering must be :sum_to_zero or :reference_first"))
    n = length(raw_cat)
    w = weights === nothing ? ones(Float64, n) : Float64.(weights)
    length(w) == n && all(x -> isfinite(x) && x > 0.0, w) ||
        throw(ArgumentError("weights must have length $n with finite positive values"))

    fnames = Tuple(b.name for b in facet_tuples)
    allowed = (:person, fnames...)
    noncenter_facet in allowed ||
        throw(ArgumentError("noncenter_facet must be one of $allowed; got $(repr(noncenter_facet))"))
    pos_set = Set{Symbol}(Symbol.(collect(positive_facets)))
    all(f -> f in allowed, pos_set) ||
        throw(ArgumentError("positive_facets entries must belong to $allowed"))

    anc_dict = Dict{Symbol,Any}(Symbol(k) => v for (k, v) in pairs(anchors))
    p_anchors = _parse_anchor_vector(person_levels, get(anc_dict, :person, nothing))
    if m === :mmle && any(isfinite, p_anchors)
        throw(ArgumentError("MMLE integrates person abilities over the population distribution and does not accept person anchors; use method = :jmle"))
    end

    fdefs = FacetDef[]
    for b in facet_tuples
        fanc = _parse_anchor_vector(b.levels, get(anc_dict, b.name, nothing))
        has_anc = any(isfinite, fanc)
        is_cent = !has_anc && (m === :mmle ? (b.name !== noncenter_facet || noncenter_facet === :person) : b.name !== noncenter_facet)
        sgn = b.name in pos_set ? 1 : -1
        push!(fdefs, FacetDef(b.name, b.levels, copy(b.index), sgn, fanc, is_cent, centering))
    end
    p_has_anc = any(isfinite, p_anchors)
    p_cent = m === :jmle && !p_has_anc && noncenter_facet !== :person
    score_k = [raw_cat[i] - first(supports[step_group[i]]) for i in 1:n]
    obs_bind = _observation_binding_hash(person_levels, person_idx, fdefs, supports, step_group, raw_cat, w)
    return Problem(
        source_kind, step_owner === :global ? :rsm : :pcm, m, n,
        copy(person_levels), copy(person_idx), p_anchors, p_cent, centering,
        fdefs, step_owner, copy(step_group), copy(step_group_levels), copy(supports),
        score_k, copy(raw_cat), w, noncenter_facet, centering, obs_bind,
    )
end

function _map_additive_categories_to_problem(categories::Vector{Int}, supports::Vector{UnitRange{Int}}, category_idx::Vector{Int})
    val_supports = Vector{UnitRange{Int}}(undef, length(supports))
    for (g, sup) in enumerate(supports)
        vals_g = categories[sup]
        rng_g = first(vals_g):last(vals_g)
        collect(rng_g) == vals_g ||
            throw(ArgumentError("unit-slope RSM/PCM requires consecutive integer category_levels within each step support (got $(vals_g)); use MRCML.custom_spec with explicit scoring matrix `B` for non-consecutive category scores"))
        val_supports[g] = rng_g
    end
    raw_scores = Int[categories[c] for c in category_idx]
    return (val_supports, raw_scores)
end

function compile_problem(s::Spec; kwargs...)
    s.allocation.identified ||
        throw(ArgumentError("F-facet design is rank-deficient / disconnected; inspect validate_design(spec)"))
    val_supports, raw_scores = _map_additive_categories_to_problem(s.categories, s.supports, s.category)
    return _compile_additive_common(:frequentist_spec, s.people, s.person, s.facets,
        s.owner, s.group, s.group_levels, val_supports, raw_scores; kwargs...)
end

function compile_problem(t::B.AdditiveFacets.Target; kwargs...)
    t.allocation.identified ||
        throw(ArgumentError("AdditiveFacets.Target is rank-deficient / disconnected; inspect validate_design(target)"))
    ftuples = [(; name = b.name, levels = b.levels, index = b.index) for b in t.facets]
    val_supports, raw_scores = _map_additive_categories_to_problem(t.categories, t.supports, t.category)
    return _compile_additive_common(:additive_facets, t.people, t.person, ftuples,
        t.owner, t.group, t.group_levels, val_supports, raw_scores; kwargs...)
end

function compile_problem(t::B.AdditiveFacets.ExplanatoryTarget; method::Symbol, kwargs...)
    m = _normalize_method(method)
    isempty(t.predictors) ||
        throw(ArgumentError("frequentist JMLE/MMLE supports pure-facet 1D RSM/PCM without continuous predictors; use Bayesian fit for predictor regressions"))
    non_person_res = [r.name for r in t.residuals if r.name !== :person && !isempty(r.raw)]
    isempty(non_person_res) ||
        throw(ArgumentError("frequentist JMLE/MMLE does not support non-person random residual blocks $non_person_res; use Bayesian fit"))
    t.allocation.identified ||
        throw(ArgumentError("ExplanatoryTarget design is not identified; inspect validate_design(target)"))
    ftuples = [(; name = b.name, levels = b.levels, index = b.index) for b in t.facets]
    val_supports, raw_scores = _map_additive_categories_to_problem(t.categories, t.supports, t.category)
    return _compile_additive_common(:explanatory_facets, t.people, t.person, ftuples,
        t.owner, t.group, t.group_levels, val_supports, raw_scores; method = m, kwargs...)
end

function compile_problem(t::B.AdditiveFacets.AbstractTarget; kwargs...)
    throw(ArgumentError("frequentist JMLE/MMLE supports 1D ordinal RSM/PCM targets only; $(typeof(t)) requires Bayesian fit"))
end

# ---------------------------------------------------------------------------
# 3. Constraint Expansion Matrix & Category-Support / Boundary Audits
# ---------------------------------------------------------------------------

function _check_step_category_support(prob::Problem, active_rows::Vector{Int})
    for g in eachindex(prob.supports)
        K_g = length(prob.supports[g])
        counts = zeros(Int, K_g)
        for r in active_rows
            prob.step_group[r] == g || continue
            counts[prob.score_k[r] + 1] += 1
        end
        # Every category from 0 to K_g - 1 must be observed for finite unpenalized step thresholds
        missing_cats = [first(prob.supports[g]) + k - 1 for k in 1:K_g if counts[k] == 0]
        if !isempty(missing_cats)
            owner_lbl = prob.step_owner === :global ? "common scale" : "$(prob.step_owner)=$(prob.step_group_levels[g])"
            throw(ArgumentError("unobserved declared category(ies) $(missing_cats) in $owner_lbl leave adjacent step thresholds unidentified under unpenalized ML; recode consecutive observed categories or use Bayesian fit with proper step priors"))
        end
    end
    return nothing
end

function build_layout(prob::Problem;
        extreme_adjustment::Real = 0.0,
        estimate_mean::Bool = false,
        estimate_sd::Bool = false)
    P = length(prob.person_levels)
    is_jmle = prob.method === :jmle

    # Classify each person's score pattern
    p_rows = [Int[] for _ in 1:P]
    for r in 1:prob.n_obs
        push!(p_rows[prob.person_idx[r]], r)
    end
    extreme_status = Vector{Symbol}(undef, P)
    for p in 1:P
        rs = p_rows[p]
        if isempty(rs)
            extreme_status[p] = :unobserved
        elseif isfinite(prob.person_anchors[p])
            extreme_status[p] = :anchored
        else
            all_min = all(r -> prob.score_k[r] == 0, rs)
            all_max = all(r -> prob.score_k[r] == length(prob.supports[prob.step_group[r]]) - 1, rs)
            extreme_status[p] = all_min ? :all_minimum : (all_max ? :all_maximum : :interior)
        end
    end

    any(==(:unobserved), extreme_status) &&
        throw(ArgumentError("one or more declared persons have zero observations"))

    # Active rows for calibration:
    # In unadjusted JMLE with uncentered person, extreme persons contribute exact 0 at +/-Inf.
    separate_extremes = is_jmle && !prob.person_centered && extreme_adjustment == 0.0
    if is_jmle && prob.person_centered && extreme_adjustment == 0.0 && any(s -> s in (:all_minimum, :all_maximum), extreme_status)
        throw(ArgumentError("centered person facet in unadjusted JMLE has extreme-score person(s), making the sum-to-zero constraint diverge; use noncenter_facet = :person or extreme_adjustment = 0.3"))
    end
    active_rows = separate_extremes ?
        [r for r in 1:prob.n_obs if !(extreme_status[prob.person_idx[r]] in (:all_minimum, :all_maximum))] :
        collect(1:prob.n_obs)
    isempty(active_rows) && throw(ArgumentError("no interior person ratings remain for JMLE calibration"))

    _check_step_category_support(prob, active_rows)

    # Build sparse expansion x_full = c_vec + J_mat * u_free
    I_rows = Int[]
    J_cols = Int[]
    V_vals = Float64[]
    c_vec = Float64[]
    full_names = String[]
    free_names = String[]
    fixed_mask = Bool[]

    full_offset = 0
    free_offset = 0

    function append_location_block!(bname::Symbol, levels::Vector{Any}, anchors::Vector{Float64},
            centered::Bool, cent_mode::Symbol; skip_mask = falses(length(levels)))
        L = length(levels)
        f_start = full_offset + 1
        u_start = free_offset + 1
        free_lvls = [l for l in 1:L if !isfinite(anchors[l]) && !skip_mask[l]]
        anc_sum = sum((isfinite(anchors[l]) ? anchors[l] : 0.0) for l in 1:L; init = 0.0)

        if !centered
            for l in 1:L
                push!(full_names, "$(bname)[$(levels[l])]")
                if isfinite(anchors[l])
                    push!(c_vec, anchors[l])
                    push!(fixed_mask, true)
                elseif skip_mask[l]
                    push!(c_vec, 0.0)
                    push!(fixed_mask, true)
                else
                    free_offset += 1
                    push!(free_names, "$(bname)[$(levels[l])]")
                    push!(c_vec, 0.0)
                    push!(fixed_mask, false)
                    push!(I_rows, full_offset + l)
                    push!(J_cols, free_offset)
                    push!(V_vals, 1.0)
                end
            end
        elseif cent_mode === :reference_first
            first_free = isempty(free_lvls) ? 0 : first(free_lvls)
            for l in 1:L
                push!(full_names, "$(bname)[$(levels[l])]")
                if isfinite(anchors[l])
                    push!(c_vec, anchors[l])
                    push!(fixed_mask, true)
                elseif l == first_free || skip_mask[l]
                    push!(c_vec, 0.0)
                    push!(fixed_mask, true)
                else
                    free_offset += 1
                    push!(free_names, "$(bname)[$(levels[l])]")
                    push!(c_vec, 0.0)
                    push!(fixed_mask, false)
                    push!(I_rows, full_offset + l)
                    push!(J_cols, free_offset)
                    push!(V_vals, 1.0)
                end
            end
        else # :sum_to_zero
            m_free = length(free_lvls)
            if m_free == 0
                for l in 1:L
                    push!(full_names, "$(bname)[$(levels[l])]")
                    push!(c_vec, isfinite(anchors[l]) ? anchors[l] : 0.0)
                    push!(fixed_mask, true)
                end
            elseif m_free == 1
                only_l = only(free_lvls)
                for l in 1:L
                    push!(full_names, "$(bname)[$(levels[l])]")
                    push!(c_vec, l == only_l ? -anc_sum : (isfinite(anchors[l]) ? anchors[l] : 0.0))
                    push!(fixed_mask, true)
                end
            else
                last_l = free_lvls[end]
                assigned_cols = Int[]
                for l in 1:L
                    push!(full_names, "$(bname)[$(levels[l])]")
                    if isfinite(anchors[l])
                        push!(c_vec, anchors[l])
                        push!(fixed_mask, true)
                    elseif skip_mask[l]
                        push!(c_vec, 0.0)
                        push!(fixed_mask, true)
                    elseif l == last_l
                        push!(c_vec, -anc_sum)
                        push!(fixed_mask, false)
                    else
                        free_offset += 1
                        push!(assigned_cols, free_offset)
                        push!(free_names, "$(bname)[$(levels[l])]")
                        push!(c_vec, 0.0)
                        push!(fixed_mask, false)
                        push!(I_rows, full_offset + l)
                        push!(J_cols, free_offset)
                        push!(V_vals, 1.0)
                    end
                end
                for col in assigned_cols
                    push!(I_rows, full_offset + last_l)
                    push!(J_cols, col)
                    push!(V_vals, -1.0)
                end
            end
        end
        full_offset += L
        return f_start:full_offset, u_start:free_offset
    end

    if is_jmle
        skip_p = BitVector([separate_extremes && (s in (:all_minimum, :all_maximum)) for s in extreme_status])
        p_full_rng, p_free_rng = append_location_block!(:person, prob.person_levels, prob.person_anchors,
            prob.person_centered, prob.person_centering; skip_mask = skip_p)
        interior_persons = [p for p in 1:P if !skip_p[p] && !isfinite(prob.person_anchors[p])]
    else
        p_full_rng = 1:0
        p_free_rng = 1:0
        interior_persons = collect(1:P)
    end

    f_full_rngs = UnitRange{Int}[]
    f_free_rngs = UnitRange{Int}[]
    for f in prob.facets
        fr, ur = append_location_block!(f.name, f.levels, f.anchors, f.centered, f.centering)
        push!(f_full_rngs, fr)
        push!(f_free_rngs, ur)
    end

    s_full_rngs = UnitRange{Int}[]
    s_free_rngs = UnitRange{Int}[]
    for g in eachindex(prob.supports)
        H = length(prob.supports[g]) - 1
        f_start = full_offset + 1
        u_start = free_offset + 1
        glbl = prob.step_owner === :global ? "Common" : string(prob.step_group_levels[g])
        if H == 1
            push!(full_names, "steps[$glbl,1]")
            push!(c_vec, 0.0)
            push!(fixed_mask, true)
            full_offset += 1
        else
            cols = Int[]
            for s in 1:(H - 1)
                free_offset += 1
                push!(cols, free_offset)
                push!(free_names, "steps[$glbl,$s]")
                push!(full_names, "steps[$glbl,$s]")
                push!(c_vec, 0.0)
                push!(fixed_mask, false)
                push!(I_rows, full_offset + s)
                push!(J_cols, free_offset)
                push!(V_vals, 1.0)
            end
            push!(full_names, "steps[$glbl,$H]")
            push!(c_vec, 0.0)
            push!(fixed_mask, false)
            for col in cols
                push!(I_rows, full_offset + H)
                push!(J_cols, col)
                push!(V_vals, -1.0)
            end
            full_offset += H
        end
        push!(s_full_rngs, f_start:full_offset)
        push!(s_free_rngs, u_start:free_offset)
    end

    n_full_structural = full_offset
    mu_idx = 0
    lsig_idx = 0
    if !is_jmle && estimate_mean
        free_offset += 1
        mu_idx = free_offset
        push!(free_names, "population_mean")
    end
    if !is_jmle && estimate_sd
        free_offset += 1
        lsig_idx = free_offset
        push!(free_names, "log_population_sd")
    end

    J_mat = sparse(I_rows, J_cols, V_vals, n_full_structural, free_offset)

    # CR5 guard: verify unadjusted JMLE active rows remain connected / full location rank
    # after removing extreme-scoring persons (catches extreme-score-only bridges).
    if separate_extremes && length(active_rows) < prob.n_obs
        loc_cols = Int[]
        append!(loc_cols, p_free_rng)
        for rng in f_free_rngs
            append!(loc_cols, rng)
        end
        if !isempty(loc_cols)
            r_rows = Int[]
            r_cols = Int[]
            r_vals = Float64[]
            for (k, r) in enumerate(active_rows)
                push!(r_rows, k); push!(r_cols, p_full_rng[prob.person_idx[r]]); push!(r_vals, 1.0)
                for fi in eachindex(f_full_rngs)
                    push!(r_rows, k); push!(r_cols, f_full_rngs[fi][prob.facets[fi].index[r]]); push!(r_vals, Float64(prob.facets[fi].sign))
                end
            end
            R_inc = sparse(r_rows, r_cols, r_vals, length(active_rows), n_full_structural)
            M_loc = R_inc * J_mat[:, loc_cols]
            dropzeros!(M_loc)
            loc_audit = B.AdditiveFacets._mrcml_spqr_rank(M_loc, free_names[loc_cols])
            if !loc_audit.full_rank
                throw(ArgumentError(
                    "Unadjusted JMLE (`extreme_adjustment = 0.0`) became rank-deficient or score-disconnected after excluding extreme-scoring persons (active rank $(loc_audit.rank)/$(length(loc_cols)), $(length(active_rows))/$(prob.n_obs) interior rows; aliased: $(loc_audit.dependent_columns)). Inspect `validate_design(spec).connectedness`, add interior bridging observations, or use `method = :mmle`, Bayesian NUTS, or positive `extreme_adjustment`."))
            end
        end
    end

    # CR5 Fischer (1981) one-sided separation guard for unadjusted JMLE:
    # Even when all margins are interior and structural rank is full, one-sided directed
    # cuts between facet subsets imply no finite unpenalized JMLE exists.
    if separate_extremes && !isempty(active_rows)
        fmeta = NamedTuple[
            (; name = f.name, levels = collect(Any, f.levels), index = f.index, sign = f.sign)
            for f in prob.facets
        ]
        fmap = Dict{Tuple{Symbol,Any},Bool}()
        for f in prob.facets
            for (l, lvl) in enumerate(f.levels)
                isfinite(f.anchors[l]) && (fmap[(f.name, lvl)] = true)
            end
        end
        cat_1based = Int[prob.score_k[r] + first(prob.supports[prob.step_group[r]]) for r in 1:prob.n_obs]
        sep = B._cr5_fischer_separation_audit(
            prob.person_levels, prob.person_idx, fmeta, cat_1based, prob.supports, prob.step_group,
            active_rows; op = nothing, fixed_map = fmap)
        if sep.separated
            reasons = vcat(
                String[String(rec.reason) for rec in sep.by_facet if rec.separated],
                String[String(trec.reason) for trec in sep.threshold_separations],
            )
            throw(ArgumentError(
                "Unadjusted JMLE (`extreme_adjustment = 0.0`) has no finite solution due to demonstrated score/threshold separation: " *
                join(reasons, " ") *
                " Inspect `validate_design(spec).one_sided_separation`, add bridging ratings, or use `method = :mmle`, Bayesian NUTS, or positive `extreme_adjustment`."))
        end
    end

    return Layout(
        n_full_structural, p_full_rng, f_full_rngs, s_full_rngs,
        p_free_rng, f_free_rngs, s_free_rngs, mu_idx, lsig_idx, free_offset,
        c_vec, J_mat, free_names, full_names, BitVector(fixed_mask),
        extreme_status, interior_persons, active_rows,
    )
end

function initial_free_vector(prob::Problem, lay::Layout; population_sd::Real = 1.0)
    u0 = zeros(Float64, lay.n_free)
    for (g, ur) in enumerate(lay.step_free_ranges)
        isempty(ur) && continue
        H = length(prob.supports[g]) - 1
        init_steps = collect(range(-1.0, 1.0; length = H))
        init_steps .-= mean(init_steps)
        for (j, col) in enumerate(ur)
            u0[col] = init_steps[j]
        end
    end
    lay.mu_free_idx > 0 && (u0[lay.mu_free_idx] = 0.0)
    lay.log_sigma_free_idx > 0 && (u0[lay.log_sigma_free_idx] = log(Float64(population_sd)))
    return u0
end

# ---------------------------------------------------------------------------
# 4. Exact Objective, Analytical Gradient & Hessian Kernels
# ---------------------------------------------------------------------------

@inline function _row_probs!(probs::AbstractVector{T}, eta::T, steps::AbstractVector{T}) where {T<:Real}
    K = length(probs)
    probs[1] = zero(T)
    mval = zero(T)
    cum = zero(T)
    @inbounds for k in 1:(K - 1)
        cum += steps[k]
        v = k * eta - cum
        probs[k + 1] = v
        if v > mval
            mval = v
        end
    end
    denom = zero(T)
    @inbounds for k in 1:K
        e = exp(probs[k] - mval)
        probs[k] = e
        denom += e
    end
    inv_d = inv(denom)
    @inbounds for k in 1:K
        probs[k] *= inv_d
    end
    return mval + log(denom)
end

function jmle_nll_and_grad!(grad_free::Union{Nothing,Vector{Float64}}, u::AbstractVector{T},
        prob::Problem, lay::Layout; extreme_adjustment::Float64 = 0.0) where {T<:Real}
    full = T.(lay.c_vec) .+ lay.J_mat * u
    g_full = grad_free === nothing ? nothing : zeros(Float64, lay.n_full_structural)
    K_max = maximum(length, prob.supports)
    pbuf = zeros(T, K_max)
    nll = zero(T)

    for r in lay.active_rows
        p = prob.person_idx[r]
        eta = full[lay.person_full_range[p]]
        @inbounds for (fi, f) in enumerate(prob.facets)
            eta += f.sign * full[lay.facet_full_ranges[fi][f.index[r]]]
        end
        g = prob.step_group[r]
        srng = lay.step_full_ranges[g]
        K_g = length(prob.supports[g])
        pv = view(pbuf, 1:K_g)
        steps_v = view(full, srng)
        log_denom = _row_probs!(pv, eta, steps_v)
        yk = prob.score_k[r]
        # Reconstruct observed numerator stably
        cum_obs = yk == 0 ? zero(T) : sum(view(steps_v, 1:yk))
        ll_r = (yk * eta - cum_obs) - log_denom
        w = prob.weights[r]
        nll -= w * ll_r

        if g_full !== nothing
            exp_k = zero(Float64)
            @inbounds for k in 1:(K_g - 1)
                exp_k += k * Float64(pv[k + 1])
            end
            d_eta = -w * (Float64(yk) - exp_k)
            g_full[lay.person_full_range[p]] += d_eta
            @inbounds for (fi, f) in enumerate(prob.facets)
                g_full[lay.facet_full_ranges[fi][f.index[r]]] += f.sign * d_eta
            end
            # Reverse cumulative P(Y >= s) for s = H_g down to 1
            p_ge = 0.0
            @inbounds for s in (K_g - 1):-1:1
                p_ge += Float64(pv[s + 1])
                obs_ge = yk >= s ? 1.0 : 0.0
                g_full[srng[s]] += w * (obs_ge - p_ge)
            end
        end
    end

    if extreme_adjustment > 0.0
        @inbounds for p in 1:length(prob.person_levels)
            st = lay.extreme_person_status[p]
            p_idx_full = lay.person_full_range[p]
            if st === :all_minimum
                nll -= extreme_adjustment * full[p_idx_full]
                g_full !== nothing && (g_full[p_idx_full] -= extreme_adjustment)
            elseif st === :all_maximum
                nll += extreme_adjustment * full[p_idx_full]
                g_full !== nothing && (g_full[p_idx_full] += extreme_adjustment)
            end
        end
    end

    if grad_free !== nothing
        mul!(grad_free, transpose(lay.J_mat), g_full)
    end
    return nll
end

"""
Exact analytical full-space Hessian `H_full` of the JMLE negative log-likelihood,
mapped into free coordinates `H_free = J' * H_full * J`. Also supports exact
O(N + d_psi^3) block Schur complement inversion when `person` is uncentered!
"""
function jmle_exact_hessian_and_schur_cov(u_hat::Vector{Float64}, prob::Problem, lay::Layout; direction_only::Bool = false)
    full = lay.c_vec .+ lay.J_mat * u_hat
    d_theta = length(lay.person_free_range)
    d_psi = lay.n_free - d_theta
    K_max = maximum(length, prob.supports)
    pbuf = zeros(Float64, K_max)
    p_ge = zeros(Float64, K_max)
    k_p_ge = zeros(Float64, K_max)

    # Check if person block in J_mat is purely diagonal 1-to-1 (uncentered person)
    can_use_schur = !prob.person_centered && d_theta > 0
    if can_use_schur
        # Build J_psi (mapping structural free coords to non-person full coords)
        psi_cols = (d_theta + 1):lay.n_free
        # Map active interior person index -> position in 1:d_theta
        p_to_free = zeros(Int, length(prob.person_levels))
        for col in lay.person_free_range
            r_idx = rowvals(lay.J_mat)[only(nzrange(lay.J_mat, col))]
            p = r_idx - first(lay.person_full_range) + 1
            p_to_free[p] = col
        end

        D_theta = zeros(Float64, d_theta)
        # Accumulate H_full_nonperson and cross person x full_nonperson, then project via J_psi
        n_np_full = lay.n_full_structural - length(lay.person_full_range)
        np_offset = last(lay.person_full_range)
        H_np_full = zeros(Float64, n_np_full, n_np_full)
        H_p_np_full = zeros(Float64, d_theta, n_np_full)
        J_np = lay.J_mat[(np_offset + 1):lay.n_full_structural, psi_cols]

        local_idx = Int[]
        local_sgn = Float64[]
        sizehint!(local_idx, length(prob.facets) + K_max)
        sizehint!(local_sgn, length(prob.facets) + K_max)

        for r in lay.active_rows
            p = prob.person_idx[r]
            eta = full[lay.person_full_range[p]]
            for (fi, f) in enumerate(prob.facets)
                eta += f.sign * full[lay.facet_full_ranges[fi][f.index[r]]]
            end
            g = prob.step_group[r]
            srng = lay.step_full_ranges[g]
            K_g = length(prob.supports[g])
            H_g = K_g - 1
            pv = view(pbuf, 1:K_g)
            _row_probs!(pv, eta, view(full, srng))
            w = prob.weights[r]

            exp_k = 0.0
            for k in 1:H_g
                exp_k += k * pv[k + 1]
            end
            var_k = 0.0
            for k in 0:H_g
                var_k += pv[k + 1] * (k - exp_k)^2
            end
            w_var = w * var_k

            acc_p = 0.0
            acc_kp = 0.0
            for s in H_g:-1:1
                pr = pv[s + 1]
                acc_p += pr
                acc_kp += s * pr
                p_ge[s] = acc_p
                k_p_ge[s] = acc_kp
            end

            u_p = p_to_free[p]
            u_p > 0 && (D_theta[u_p] += w_var)

            # Non-person location indices & signs
            empty!(local_idx)
            empty!(local_sgn)
            for (fi, f) in enumerate(prob.facets)
                push!(local_idx, lay.facet_full_ranges[fi][f.index[r]] - np_offset)
                push!(local_sgn, Float64(f.sign))
            end
            n_f = length(local_idx)
            # Location-location & person-location blocks
            for a in 1:n_f
                ia = local_idx[a]
                sa = local_sgn[a]
                u_p > 0 && (H_p_np_full[u_p, ia] += sa * w_var)
                for b in 1:n_f
                    H_np_full[ia, local_idx[b]] += sa * local_sgn[b] * w_var
                end
            end
            # Cross location-step & person-step, plus step-step
            for s in 1:H_g
                is_idx = srng[s] - np_offset
                # d^2(-ll)/(d_eta d_tau_s) = -w * (E[Y I(Y>=s)] - E[Y] P(Y>=s))
                h_eta_s = -w * (k_p_ge[s] - exp_k * p_ge[s])
                u_p > 0 && (H_p_np_full[u_p, is_idx] += h_eta_s)
                for a in 1:n_f
                    ia = local_idx[a]
                    v_cross = local_sgn[a] * h_eta_s
                    H_np_full[ia, is_idx] += v_cross
                    H_np_full[is_idx, ia] += v_cross
                end
                for t in 1:H_g
                    it_idx = srng[t] - np_offset
                    p_max = p_ge[max(s, t)]
                    H_np_full[is_idx, it_idx] += w * (p_max - p_ge[s] * p_ge[t])
                end
            end
        end

        H_psi_psi = Symmetric(Matrix(transpose(J_np) * H_np_full * J_np))
        H_theta_psi = H_p_np_full * J_np
        if !all(x -> isfinite(x) && x > 0, D_theta)
            direction_only && return nothing
            return (; ok=false, full_se=fill(NaN, lay.n_full_structural), cov_psi=nothing,
                    S_psi=fill(NaN, d_psi, d_psi), D_theta, H_theta_psi, min_eig=0.0, cond=Inf)
        end
        inv_D = 1.0 ./ D_theta
        # Schur complement S_psi = H_psi_psi - H_theta_psi' * diag(inv_D) * H_theta_psi
        weighted_cross = H_theta_psi .* sqrt.(inv_D)
        S_psi = Symmetric(Matrix(H_psi_psi) - transpose(weighted_cross) * weighted_cross)
        ch = cholesky(S_psi; check = false)
        pd_ok = issuccess(ch) && all(>(0.0), D_theta)
        if direction_only
            return pd_ok ? (; factor=ch, diagonal=D_theta, cross=H_theta_psi) : nothing
        end
        if !pd_ok
            return (; ok = false, full_se = fill(NaN, lay.n_full_structural), cov_psi = nothing,
                S_psi = Matrix(S_psi), D_theta, H_theta_psi, min_eig = minimum(eigvals(S_psi); init=Inf), cond = Inf)
        end
        cov_psi = inv(ch)
        eigs = eigvals(S_psi)
        min_eig = min(minimum(D_theta), minimum(eigs; init=Inf))
        max_eig = max(maximum(D_theta), maximum(eigs; init=0.0))
        cond_num = max_eig / max(min_eig, eps(Float64))

        # Full SEs:
        # 1) Non-person facets & steps: diag(J_np * cov_psi * J_np')
        cov_np_full = Matrix(J_np * cov_psi * transpose(J_np))
        full_se = fill(NaN, lay.n_full_structural)
        for i in 1:n_np_full
            idx_full = np_offset + i
            lay.fixed_mask[idx_full] && continue
            v = cov_np_full[i, i]
            full_se[idx_full] = v >= -1e-12 ? sqrt(max(v, 0.0)) : NaN
        end
        # 2) Interior persons: inv_D[u] + sum_row((inv_D[u] * H_theta_psi[u, :])' * cov_psi * (...))
        A_mat = (H_theta_psi .* inv_D) # d_theta x d_psi
        B_mat = A_mat * cov_psi
        p_var_free = inv_D .+ vec(sum(A_mat .* B_mat; dims = 2))
        for p in 1:length(prob.person_levels)
            u_p = p_to_free[p]
            u_p > 0 || continue
            full_se[lay.person_full_range[p]] = sqrt(max(p_var_free[u_p], 0.0))
        end
        return (; ok = true, full_se, cov_np_full, np_offset, cov_psi, S_psi = Matrix(S_psi),
            D_theta, H_theta_psi, min_eig, cond = cond_num)
    else
        # General fallback (e.g. noncenter_facet != :person): exact ForwardDiff Hessian on u_hat
        H_free = Symmetric(ForwardDiff.hessian(z -> jmle_nll_and_grad!(nothing, z, prob, lay), u_hat))
        ch = cholesky(H_free; check = false)
        eigs = eigvals(H_free)
        min_eig = isempty(eigs) ? NaN : minimum(eigs)
        cond_num = isempty(eigs) || min_eig <= 0 ? Inf : maximum(eigs) / min_eig
        if !issuccess(ch)
            return (; ok = false, full_se = fill(NaN, lay.n_full_structural), cov_psi = nothing,
                S_psi = Matrix(H_free), D_theta = Float64[], H_theta_psi = zeros(0, 0), min_eig, cond = cond_num)
        end
        cov_free = inv(ch)
        cov_full = Matrix(lay.J_mat * cov_free * transpose(lay.J_mat))
        full_se = [lay.fixed_mask[i] ? NaN : sqrt(max(cov_full[i, i], 0.0)) for i in 1:lay.n_full_structural]
        return (; ok = true, full_se, cov_full, cov_psi = cov_free, S_psi = Matrix(H_free),
            D_theta = Float64[], H_theta_psi = zeros(0, 0), min_eig, cond = cond_num)
    end
end

struct _FreqMMLEPatternScratch
    n_patterns::Int
    pat_group::Vector{Int}
    pat_facet_full::Matrix{Int}
    facet_signs::Vector{Float64}
    pat_offsets::Vector{Int}
    pat_of_row::Vector{Int}
    obs_slot::Vector{Int}
    M_tot::Int
    std_nodes::Vector{Float64}
    log_w::Vector{Float64}
    full_buf::Vector{Float64}
    pat_eta::Vector{Float64}
    logp_slot::Vector{Float64}
    ll_pq::Matrix{Float64}
    post_w::Matrix{Float64}
    slot_acc::Vector{Float64}
    pat_w::Vector{Float64}
    g_full::Vector{Float64}
    pbuf::Vector{Float64}
end

function _build_freq_mmle_scratch(prob::Problem, lay::Layout, base_quad)
    F = length(prob.facets)
    n = prob.n_obs
    P = length(prob.person_levels)
    Q = length(base_quad.std_nodes)
    K_max = maximum(length, prob.supports)

    pat_map = Dict{Tuple{Int,Tuple},Int}()
    pat_group = Int[]
    pat_fcols = Vector{Int}[]
    pat_of_row = Vector{Int}(undef, n)

    for r in 1:n
        g = prob.step_group[r]
        key = (g, Tuple(prob.facets[fi].index[r] for fi in 1:F))
        u = get!(pat_map, key) do
            push!(pat_group, g)
            push!(pat_fcols, Int[lay.facet_full_ranges[fi][prob.facets[fi].index[r]] for fi in 1:F])
            length(pat_group)
        end
        pat_of_row[r] = u
    end

    U = length(pat_group)
    pat_facet_full = Matrix{Int}(undef, F, U)
    for u in 1:U, fi in 1:F
        pat_facet_full[fi, u] = pat_fcols[u][fi]
    end
    facet_signs = Float64[Float64(f.sign) for f in prob.facets]

    pat_offsets = Vector{Int}(undef, U)
    M_tot = 0
    for u in 1:U
        pat_offsets[u] = M_tot
        M_tot += length(prob.supports[pat_group[u]])
    end
    obs_slot = Vector{Int}(undef, n)
    @inbounds for r in 1:n
        obs_slot[r] = pat_offsets[pat_of_row[r]] + prob.score_k[r] + 1
    end
    log_w = Float64[w > 0.0 ? log(w) : -Inf for w in base_quad.weights]

    return _FreqMMLEPatternScratch(
        U, pat_group, pat_facet_full, facet_signs, pat_offsets, pat_of_row, obs_slot, M_tot,
        collect(Float64, base_quad.std_nodes), log_w,
        Vector{Float64}(undef, lay.n_full_structural),
        Vector{Float64}(undef, U),
        Vector{Float64}(undef, M_tot),
        Matrix{Float64}(undef, P, Q),
        Matrix{Float64}(undef, P, Q),
        Vector{Float64}(undef, M_tot),
        Vector{Float64}(undef, U),
        Vector{Float64}(undef, lay.n_full_structural),
        Vector{Float64}(undef, K_max),
    )
end

function mmle_nll_and_grad!(grad_free::Union{Nothing,AbstractVector}, u::AbstractVector{T},
        prob::Problem, lay::Layout, base_quad;
        fixed_sd::Float64 = 1.0,
        scratch::Union{Nothing,_FreqMMLEPatternScratch} = nothing) where {T<:Real}
    sc = scratch === nothing ? _build_freq_mmle_scratch(prob, lay, base_quad) : scratch
    use_f64 = (T === Float64) && (grad_free === nothing || eltype(grad_free) === Float64)

    full = if use_f64
        copyto!(sc.full_buf, lay.c_vec)
        mul!(sc.full_buf, lay.J_mat, u, 1.0, 1.0)
        sc.full_buf
    else
        T.(lay.c_vec) .+ lay.J_mat * u
    end
    mu = lay.mu_free_idx > 0 ? u[lay.mu_free_idx] : zero(T)
    sigma = lay.log_sigma_free_idx > 0 ? exp(u[lay.log_sigma_free_idx]) : T(fixed_sd)
    !(isfinite(sigma) && 1e-8 <= sigma <= 1e4) && return T(Inf)

    U = sc.n_patterns
    F = length(sc.facet_signs)
    Q = length(sc.std_nodes)
    P = length(prob.person_levels)
    K_max = maximum(length, prob.supports)

    pat_eta = use_f64 ? sc.pat_eta : Vector{T}(undef, U)
    @inbounds for u_pat in 1:U
        s = mu
        for fi in 1:F
            s += T(sc.facet_signs[fi]) * full[sc.pat_facet_full[fi, u_pat]]
        end
        pat_eta[u_pat] = s
    end

    if use_f64 && 2U > prob.n_obs
        fast = _ordinal_scalar_mmle!(grad_free, prob, lay, sc, sigma)
        isnothing(fast) || return fast
    end

    logp_slot = use_f64 ? sc.logp_slot : Vector{T}(undef, sc.M_tot)
    ll_pq = use_f64 ? fill!(sc.ll_pq, 0.0) : zeros(T, P, Q)

    @inbounds for q in 1:Q
        sc.log_w[q] == -Inf && continue
        theta_shift = sigma * T(sc.std_nodes[q])
        for u_pat in 1:U
            eta = pat_eta[u_pat] + theta_shift
            g = sc.pat_group[u_pat]
            srng = lay.step_full_ranges[g]
            K_g = length(prob.supports[g])
            m0 = sc.pat_offsets[u_pat]
            logp_slot[m0 + 1] = zero(T)
            mmax = zero(T)
            cum = zero(T)
            for k in 1:(K_g - 1)
                cum += full[srng[k]]
                v = k * eta - cum
                logp_slot[m0 + k + 1] = v
                v > mmax && (mmax = v)
            end
            denom = zero(T)
            for k in 1:K_g
                denom += exp(logp_slot[m0 + k] - mmax)
            end
            ld = mmax + log(denom)
            for k in 1:K_g
                logp_slot[m0 + k] -= ld
            end
        end
        for r in 1:prob.n_obs
            ll_pq[prob.person_idx[r], q] += T(prob.weights[r]) * logp_slot[sc.obs_slot[r]]
        end
    end

    post_w = grad_free === nothing ? nothing : (use_f64 ? sc.post_w : Matrix{T}(undef, P, Q))
    total_ll = zero(T)
    @inbounds for p in 1:P
        m_t = T(-Inf)
        for q in 1:Q
            sc.log_w[q] == -Inf && continue
            cand = ll_pq[p, q] + T(sc.log_w[q])
            cand > m_t && (m_t = cand)
        end
        s_exp = zero(T)
        for q in 1:Q
            sc.log_w[q] == -Inf && continue
            s_exp += exp(ll_pq[p, q] + T(sc.log_w[q]) - m_t)
        end
        lp = m_t + log(s_exp)
        total_ll += lp
        if post_w !== nothing
            for q in 1:Q
                post_w[p, q] = sc.log_w[q] == -Inf ? zero(T) : exp(ll_pq[p, q] + T(sc.log_w[q]) - lp)
            end
        end
    end

    if grad_free !== nothing
        g_full = use_f64 ? fill!(sc.g_full, 0.0) : zeros(T, lay.n_full_structural)
        slot_acc = use_f64 ? sc.slot_acc : Vector{T}(undef, sc.M_tot)
        pat_w = use_f64 ? sc.pat_w : Vector{T}(undef, U)
        pbuf = use_f64 ? sc.pbuf : Vector{T}(undef, K_max)
        g_mu = zero(T)
        g_lsig = zero(T)

        @inbounds for q in 1:Q
            sc.log_w[q] == -Inf && continue
            zq = sc.std_nodes[q]
            theta_shift = sigma * T(zq)
            fill!(slot_acc, zero(T))
            fill!(pat_w, zero(T))
            for r in 1:prob.n_obs
                pw = post_w[prob.person_idx[r], q]
                pw == zero(T) && continue
                w_pw = T(prob.weights[r]) * pw
                slot_acc[sc.obs_slot[r]] += w_pw
                pat_w[sc.pat_of_row[r]] += w_pw
            end

            for u_pat in 1:U
                wu = pat_w[u_pat]
                wu == zero(T) && continue
                eta = pat_eta[u_pat] + theta_shift
                g = sc.pat_group[u_pat]
                srng = lay.step_full_ranges[g]
                K_g = length(prob.supports[g])
                pv = view(pbuf, 1:K_g)
                _row_probs!(pv, eta, view(full, srng))
                m0 = sc.pat_offsets[u_pat]
                obs_k_sum = zero(T)
                exp_k = zero(T)
                for k in 1:(K_g - 1)
                    obs_k_sum += k * slot_acc[m0 + k + 1]
                    exp_k += k * pv[k + 1]
                end
                d_eta = -(obs_k_sum - wu * exp_k)
                g_mu += d_eta
                g_lsig += d_eta * theta_shift
                for fi in 1:F
                    g_full[sc.pat_facet_full[fi, u_pat]] += T(sc.facet_signs[fi]) * d_eta
                end
                p_ge = zero(T)
                obs_ge = zero(T)
                for s in (K_g - 1):-1:1
                    p_ge += pv[s + 1]
                    obs_ge += slot_acc[m0 + s + 1]
                    g_full[srng[s]] += obs_ge - wu * p_ge
                end
            end
        end
        fill!(grad_free, zero(eltype(grad_free)))
        mul!(grad_free, transpose(lay.J_mat), g_full)
        lay.mu_free_idx > 0 && (grad_free[lay.mu_free_idx] = g_mu)
        lay.log_sigma_free_idx > 0 && (grad_free[lay.log_sigma_free_idx] = g_lsig)
    end
    return -total_ll
end

# ---------------------------------------------------------------------------
# 5. Two-Loop L-BFGS + Exact Damped Newton-Cholesky Polish
# ---------------------------------------------------------------------------

function _optimize_lbfgs(fg!, x0::Vector{Float64};
        maxit::Int = 400, gtol::Float64 = 1e-9, ftol::Float64 = 1e-12, m_hist::Int = 12)
    n = length(x0)
    x = copy(x0)
    g = zeros(Float64, n)
    f = fg!(g, x)
    n == 0 && return (; x, f, g, nit = 0, nfev = 1, converged = true)

    s_list = Vector{Float64}[]
    y_list = Vector{Float64}[]
    rho_list = Float64[]

    x_new = similar(x)
    g_new = similar(g)
    q = similar(g)
    d = similar(g)
    nfev = 1
    nit = 0
    converged = norm(g, Inf) <= gtol

    while !converged && nit < maxit
        nit += 1
        # L-BFGS two-loop recursion
        copyto!(q, g)
        k_len = length(s_list)
        alphas = zeros(Float64, k_len)
        for i in k_len:-1:1
            alphas[i] = rho_list[i] * dot(s_list[i], q)
            axpy!(-alphas[i], y_list[i], q)
        end
        if k_len > 0
            gamma = dot(s_list[end], y_list[end]) / max(dot(y_list[end], y_list[end]), 1e-30)
            q .*= clamp(gamma, 1e-6, 1e6)
        end
        for i in 1:k_len
            beta = rho_list[i] * dot(y_list[i], q)
            axpy!(alphas[i] - beta, s_list[i], q)
        end
        @. d = -q
        dg = dot(d, g)
        if !(isfinite(dg) && dg < 0.0)
            @. d = -g
            dg = -dot(g, g)
            empty!(s_list); empty!(y_list); empty!(rho_list)
        end

        # Bracket a Wolfe step. Near the roundoff floor use the derivative
        # bounds of Hager–Zhang's approximate Wolfe test.
        step = 1.0
        lower, upper = 0.0, Inf
        accepted = false
        f_try = f
        for _ in 1:45
            @. x_new = x + step * d
            x_new == x && break
            f_try = fg!(g_new, x_new)
            nfev += 1
            finite = isfinite(f_try) && all(isfinite, g_new)
            next_slope = finite ? dot(d,g_new) : Inf
            decrease = finite && f_try <= f + 1e-4 * step * dg
            near_floor = finite && abs(f_try - f) <= 32eps(max(1.0, abs(f)))
            if next_slope >= 0.9 * dg &&
                    (decrease || (near_floor && next_slope <= (2e-4 - 1) * dg))
                accepted = true
                break
            end
            if (decrease || near_floor) && next_slope < 0.9 * dg
                lower = step
            else
                upper = step
            end
            step = isfinite(upper) ? (lower + upper) / 2 : 2 * step
        end
        if !accepted
            break
        end

        s_vec = x_new .- x
        y_vec = g_new .- g
        sy = dot(s_vec, y_vec)
        if sy > 1e-14 * norm(s_vec) * norm(y_vec)
            if length(s_list) >= m_hist
                popfirst!(s_list); popfirst!(y_list); popfirst!(rho_list)
            end
            push!(s_list, s_vec)
            push!(y_list, y_vec)
            push!(rho_list, 1.0 / sy)
        end

        f_prev = f
        copyto!(x, x_new)
        copyto!(g, g_new)
        f = f_try
        if norm(g, Inf) <= gtol || (abs(f_prev - f) <= ftol * max(1.0, abs(f)) && norm(g, Inf) <= 100 * gtol)
            converged = true
        end
    end
    return (; x, f, g, nit, nfev, converged = norm(g, Inf) <= max(gtol * 10, 1e-6))
end

# Each free person contributes one diagonal element; only the structural Schur block is factored.
function _joint_schur_direction(block, g)
    isnothing(block) && return nothing
    n = length(block.diagonal)
    gt = view(g, 1:n)
    gx = view(g, n+1:length(g))
    dx = block.factor \ (block.cross' * (gt ./ block.diagonal) .- gx)
    return vcat(-((gt .+ block.cross * dx) ./ block.diagonal), dx)
end

function _fit_joint_newton(fg!, direction, initial; maxit, gtol)
    x = copy(initial)
    g = similar(x)
    f = fg!(g, x)
    evaluations = 1
    iterations = 0
    candidate = similar(x)
    next_gradient = similar(g)
    fallback_used = false
    tolerance = min(1e-11, gtol)
    while iterations < maxit && norm(g, Inf) > tolerance
        dx = direction(x, g)
        slope = isnothing(dx) ? NaN : dot(g, dx)
        accepted = false
        if isfinite(slope) && slope < 0
            step = 1.0
            for _ in 1:25
                @. candidate = x + step * dx
                candidate == x && break
                next_f = fg!(next_gradient, candidate)
                evaluations += 1
                # Near the optimum the objective can round upward while the score drops to zero.
                if isfinite(next_f) && all(isfinite, next_gradient) &&
                        (next_f <= f + 1e-4 * step * slope ||
                         (next_f <= f + 32eps(max(abs(f), 1.0)) && norm(next_gradient, Inf) < 0.5 * norm(g, Inf)))
                    x, candidate = candidate, x
                    g, next_gradient = next_gradient, g
                    f = next_f
                    accepted = true
                    iterations += 1
                    break
                end
                step *= 0.5
            end
        end
        if !accepted
            fallback_used && break
            opt = _optimize_lbfgs(fg!, x; maxit=maxit-iterations, gtol)
            x, f, g = opt.x, opt.f, opt.g
            iterations += opt.nit
            evaluations += opt.nfev
            fallback_used = true
        end
    end
    return (; x, f, g, nit=iterations, nfev=evaluations)
end

include("frequentist_louis.jl")

function _polish_mmle_newton!(x::Vector{Float64}, prob::Problem, lay::Layout, base_quad;
        fixed_sd::Float64 = 1.0, max_steps::Int = 12, gtol::Float64 = 1e-11,
        scratch::Union{Nothing,_FreqMMLEPatternScratch} = nothing)
    sc = scratch === nothing ? _build_freq_mmle_scratch(prob, lay, base_quad) : scratch
    nf = lay.n_free
    g = zeros(Float64, nf)
    f = mmle_nll_and_grad!(g, x, prob, lay, base_quad; fixed_sd, scratch = sc)
    (nf == 0 || nf > 2000) && return (; x, f, g, steps = 0, dec = norm(g, Inf))
    steps_taken = 0
    dec = norm(g, Inf)
    for _ in 1:max_steps
        norm(g, Inf) <= gtol && break
        H = _ordinal_louis(x, prob, lay, base_quad, fixed_sd, sc)
        ch = cholesky(H; check = false)
        if !issuccess(ch)
            # Small Levenberg-Marquardt shift if slightly nonconvex far from optimum
            lam = max(1e-6, -minimum(eigvals(Matrix(H))) + 1e-5)
            ch = cholesky(Symmetric(Matrix(H) + lam * I); check = false)
            issuccess(ch) || break
        end
        dx = -(ch \ g)
        dg = dot(g, dx)
        dg < 0.0 || break
        dec = -dg
        step = 1.0
        g_try = similar(g)
        improved = false
        for _ in 1:25
            x_try = x .+ step .* dx
            f_try = mmle_nll_and_grad!(g_try, x_try, prob, lay, base_quad; fixed_sd, scratch = sc)
            if isfinite(f_try) && (f_try <= f + 1e-4 * step * dg || norm(g_try, Inf) < 0.5 * norm(g, Inf))
                copyto!(x, x_try)
                copyto!(g, g_try)
                f = f_try
                improved = true
                steps_taken += 1
                break
            end
            step *= 0.5
        end
        improved || break
    end
    return (; x, f, g, steps = steps_taken, dec)
end

function _em_warmstart_mmle!(x::Vector{Float64}, prob::Problem, lay::Layout, base_quad;
        fixed_sd::Float64 = 1.0, em_iters::Int = 8,
        scratch::Union{Nothing,_FreqMMLEPatternScratch} = nothing)
    sc = scratch === nothing ? _build_freq_mmle_scratch(prob, lay, base_quad) : scratch
    U = sc.n_patterns
    F = length(sc.facet_signs)
    P = length(prob.person_levels)
    Q = length(sc.std_nodes)
    d_struct = lay.n_free - Int(lay.mu_free_idx > 0) - Int(lay.log_sigma_free_idx > 0)
    J_struct = d_struct > 0 ? lay.J_mat[:, 1:d_struct] : nothing
    u_tmp = similar(x)
    slot_q = Matrix{Float64}(undef, sc.M_tot, Q)
    pat_wq = Matrix{Float64}(undef, U, Q)

    for _ in 1:em_iters
        copyto!(sc.full_buf, lay.c_vec)
        mul!(sc.full_buf, lay.J_mat, x, 1.0, 1.0)
        full = sc.full_buf
        mu = lay.mu_free_idx > 0 ? x[lay.mu_free_idx] : 0.0
        sigma = lay.log_sigma_free_idx > 0 ? clamp(exp(x[lay.log_sigma_free_idx]), 0.05, 10.0) : fixed_sd

        @inbounds for u_pat in 1:U
            s = mu
            for fi in 1:F
                s += sc.facet_signs[fi] * full[sc.pat_facet_full[fi, u_pat]]
            end
            sc.pat_eta[u_pat] = s
        end

        ll_pq = fill!(sc.ll_pq, 0.0)
        logp_slot = sc.logp_slot
        @inbounds for q in 1:Q
            sc.log_w[q] == -Inf && continue
            th_q = sigma * sc.std_nodes[q]
            for u_pat in 1:U
                eta = sc.pat_eta[u_pat] + th_q
                g = sc.pat_group[u_pat]
                srng = lay.step_full_ranges[g]
                K_g = length(prob.supports[g])
                m0 = sc.pat_offsets[u_pat]
                logp_slot[m0 + 1] = 0.0
                mmax = 0.0
                cum = 0.0
                for k in 1:(K_g - 1)
                    cum += full[srng[k]]
                    v = k * eta - cum
                    logp_slot[m0 + k + 1] = v
                    v > mmax && (mmax = v)
                end
                denom = 0.0
                for k in 1:K_g
                    denom += exp(logp_slot[m0 + k] - mmax)
                end
                ld = mmax + log(denom)
                for k in 1:K_g
                    logp_slot[m0 + k] -= ld
                end
            end
            for r in 1:prob.n_obs
                ll_pq[prob.person_idx[r], q] += prob.weights[r] * logp_slot[sc.obs_slot[r]]
            end
        end

        post_w = sc.post_w
        @inbounds for p in 1:P
            mval = -Inf
            for q in 1:Q
                sc.log_w[q] == -Inf && continue
                mval = max(mval, ll_pq[p, q] + sc.log_w[q])
            end
            s_exp = 0.0
            for q in 1:Q
                sc.log_w[q] == -Inf && continue
                s_exp += exp(ll_pq[p, q] + sc.log_w[q] - mval)
            end
            lp = mval + log(s_exp)
            for q in 1:Q
                post_w[p, q] = sc.log_w[q] == -Inf ? 0.0 : exp(ll_pq[p, q] + sc.log_w[q] - lp)
            end
        end

        if lay.mu_free_idx > 0
            mu_acc = 0.0
            @inbounds for p in 1:P, q in 1:Q
                mu_acc += post_w[p, q] * (mu + sigma * sc.std_nodes[q])
            end
            mu = mu_acc / P
            x[lay.mu_free_idx] = mu
        end
        if lay.log_sigma_free_idx > 0
            v_acc = 0.0
            mu_cur = mu
            sig_cur = sigma
            @inbounds for p in 1:P, q in 1:Q
                th_q = (lay.mu_free_idx > 0 ? mu_cur : 0.0) + sig_cur * sc.std_nodes[q]
                d_th = th_q - mu_cur
                v_acc += post_w[p, q] * (d_th * d_th)
            end
            x[lay.log_sigma_free_idx] = 0.5 * log(clamp(v_acc / P, 0.05^2, 10.0^2))
            sigma = exp(x[lay.log_sigma_free_idx])
        end

        if d_struct > 0 && J_struct !== nothing
            fill!(slot_q, 0.0)
            fill!(pat_wq, 0.0)
            @inbounds for q in 1:Q
                sc.log_w[q] == -Inf && continue
                for r in 1:prob.n_obs
                    pw = post_w[prob.person_idx[r], q]
                    pw == 0.0 && continue
                    w_pw = prob.weights[r] * pw
                    slot_q[sc.obs_slot[r], q] += w_pw
                    pat_wq[sc.pat_of_row[r], q] += w_pw
                end
            end
            mu_m = mu
            sig_m = sigma
            function mstep_fg!(gs, xs)
                copyto!(u_tmp, x)
                u_tmp[1:d_struct] .= xs
                copyto!(sc.full_buf, lay.c_vec)
                mul!(sc.full_buf, lay.J_mat, u_tmp, 1.0, 1.0)
                full_m = sc.full_buf
                @inbounds for u_pat in 1:U
                    s = mu_m
                    for fi in 1:F
                        s += sc.facet_signs[fi] * full_m[sc.pat_facet_full[fi, u_pat]]
                    end
                    sc.pat_eta[u_pat] = s
                end
                g_full = fill!(sc.g_full, 0.0)
                pbuf = sc.pbuf
                val = 0.0
                @inbounds for q in 1:Q
                    sc.log_w[q] == -Inf && continue
                    th_shift = sig_m * sc.std_nodes[q]
                    for u_pat in 1:U
                        wu = pat_wq[u_pat, q]
                        wu == 0.0 && continue
                        eta = sc.pat_eta[u_pat] + th_shift
                        g_id = sc.pat_group[u_pat]
                        srng = lay.step_full_ranges[g_id]
                        K_g = length(prob.supports[g_id])
                        pv = view(pbuf, 1:K_g)
                        ld = _row_probs!(pv, eta, view(full_m, srng))
                        m0 = sc.pat_offsets[u_pat]
                        obs_k_sum = 0.0
                        exp_k = 0.0
                        cum_step_loss = 0.0
                        cum_s = 0.0
                        for k in 1:(K_g - 1)
                            cum_s += full_m[srng[k]]
                            sa = slot_q[m0 + k + 1, q]
                            obs_k_sum += k * sa
                            cum_step_loss += cum_s * sa
                            exp_k += k * pv[k + 1]
                        end
                        val -= (obs_k_sum * eta - cum_step_loss) - wu * ld
                        d_eta = -(obs_k_sum - wu * exp_k)
                        for fi in 1:F
                            g_full[sc.pat_facet_full[fi, u_pat]] += sc.facet_signs[fi] * d_eta
                        end
                        p_ge = 0.0
                        obs_ge = 0.0
                        for s in (K_g - 1):-1:1
                            p_ge += pv[s + 1]
                            obs_ge += slot_q[m0 + s + 1, q]
                            g_full[srng[s]] += obs_ge - wu * p_ge
                        end
                    end
                end
                mul!(gs, transpose(J_struct), g_full)
                return val
            end
            res_m = _optimize_lbfgs(mstep_fg!, x[1:d_struct]; maxit = 12, gtol = 1e-5)
            x[1:d_struct] .= res_m.x
        end
    end
    return x
end

# ---------------------------------------------------------------------------
# 6. Fixed-Calibration Person Scoring (EAP, Warm WLE, Fixed-Calibration MLE)
# ---------------------------------------------------------------------------

function _eval_person_theta(theta::Float64, rows::Vector{Int}, base_eta::Vector{Float64},
        full::Vector{Float64}, prob::Problem, lay::Layout; weighted::Bool)
    K_max = maximum(length, prob.supports)
    pbuf = zeros(Float64, K_max)
    ll = 0.0
    score = 0.0
    info = 0.0
    mu3 = 0.0
    for r in rows
        eta = theta + base_eta[r]
        g = prob.step_group[r]
        srng = lay.step_full_ranges[g]
        K_g = length(prob.supports[g])
        pv = view(pbuf, 1:K_g)
        steps_v = view(full, srng)
        ld = _row_probs!(pv, eta, steps_v)
        yk = prob.score_k[r]
        cum_obs = yk == 0 ? 0.0 : sum(view(steps_v, 1:yk))
        w = prob.weights[r]
        ll += w * ((yk * eta - cum_obs) - ld)
        m1 = 0.0
        for k in 1:(K_g - 1)
            m1 += k * pv[k + 1]
        end
        m2 = 0.0
        m3 = 0.0
        for k in 0:(K_g - 1)
            d = k - m1
            d2 = d * d
            m2 += pv[k + 1] * d2
            m3 += pv[k + 1] * d2 * d
        end
        score += w * (yk - m1)
        info += w * m2
        mu3 += w * m3
    end
    warm = info > 1e-12 ? 0.5 * mu3 / info : NaN
    adj_score = weighted ? (isfinite(warm) ? score + warm : NaN) : score
    return (; ll, score, info, mu3, warm, adj_score)
end

function _solve_person_root(rows::Vector{Int}, base_eta::Vector{Float64}, full::Vector{Float64},
        prob::Problem, lay::Layout; weighted::Bool, target_shift::Float64 = 0.0, max_abs::Float64 = 25.0)
    f_val(th) = _eval_person_theta(th, rows, base_eta, full, prob, lay; weighted).adj_score + target_shift
    v0 = f_val(0.0)
    if isfinite(v0) && abs(v0) <= 1e-12
        ev = _eval_person_theta(0.0, rows, base_eta, full, prob, lay; weighted)
        return (; estimate = 0.0, se = ev.info > 0 ? 1.0 / sqrt(ev.info) : NaN, residual = abs(v0), converged = true)
    end
    rad = 2.0
    lo = NaN
    hi = NaN
    flo = NaN
    fhi = NaN
    while rad <= max_abs
        fl = f_val(-rad)
        fr = f_val(rad)
        if isfinite(fl) && isfinite(fr) && fl >= 0.0 && fr <= 0.0
            lo = -rad; hi = rad; flo = fl; fhi = fr
            break
        end
        rad *= 2.0
    end
    if !isfinite(lo)
        return (; estimate = NaN, se = NaN, residual = NaN, converged = false)
    end
    # Safeguarded Newton + bisection on [lo, hi] (monotone decreasing score -> fl >= 0 >= fr)
    th = 0.5 * (lo + hi)
    for _ in 1:80
        ev = _eval_person_theta(th, rows, base_eta, full, prob, lay; weighted)
        fv = ev.adj_score + target_shift
        if !isfinite(fv)
            th = 0.5 * (lo + hi)
            continue
        end
        abs(fv) <= 1e-12 && break
        if fv > 0.0
            lo = th; flo = fv
        else
            hi = th; fhi = fv
        end
        (hi - lo) <= 1e-13 * max(1.0, abs(th)) && break
        # Approximate derivative of adjusted score ~ -info
        if ev.info > 1e-10
            th_new = th + fv / ev.info
            if lo < th_new < hi
                th = th_new
                continue
            end
        end
        th = 0.5 * (lo + hi)
    end
    ev_f = _eval_person_theta(th, rows, base_eta, full, prob, lay; weighted)
    res = abs(ev_f.adj_score + target_shift)
    return (; estimate = th, se = ev_f.info > 0 ? 1.0 / sqrt(ev_f.info) : NaN,
        residual = res, converged = res <= 1e-7)
end

function _weighted_quantiles(nodes::Vector{Float64}, weights::Vector{Float64}, qs = (0.05, 0.50, 0.95))
    perm = sortperm(nodes)
    sn = nodes[perm]
    sw = weights[perm] ./ sum(weights)
    cdf = cumsum(sw)
    return [sn[clamp(searchsortedfirst(cdf, q), 1, length(sn))] for q in qs]
end

function compute_person_scores(full::Vector{Float64}, prob::Problem, lay::Layout;
        quad = nothing, mu_hat::Float64 = 0.0, sigma_hat::Float64 = 1.0,
        jmle_full_se::Union{Nothing,Vector{Float64}} = nothing,
        extreme_adjustment::Float64 = 0.0)
    P = length(prob.person_levels)
    p_rows = [Int[] for _ in 1:P]
    for r in 1:prob.n_obs
        push!(p_rows[prob.person_idx[r]], r)
    end
    base_eta = zeros(Float64, prob.n_obs)
    for r in 1:prob.n_obs
        s = 0.0
        for (fi, f) in enumerate(prob.facets)
            s += f.sign * full[lay.facet_full_ranges[fi][f.index[r]]]
        end
        base_eta[r] = s
    end

    # EAP if MMLE
    eap_vals = fill(NaN, P)
    eap_sds = fill(NaN, P)
    eap_q05 = fill(NaN, P)
    eap_q50 = fill(NaN, P)
    eap_q95 = fill(NaN, P)
    if prob.method === :mmle && quad !== nothing
        Q = length(quad.std_nodes)
        theta_grid = [mu_hat + sigma_hat * z for z in quad.std_nodes]
        log_w = [w > 0.0 ? log(w) : -Inf for w in quad.weights]
        K_max = maximum(length, prob.supports)
        pbuf = zeros(Float64, K_max)
        for p in 1:P
            lls = fill(-Inf, Q)
            for q in 1:Q
                log_w[q] == -Inf && continue
                s_ll = 0.0
                th_q = theta_grid[q]
                for r in p_rows[p]
                    eta = th_q + base_eta[r]
                    g = prob.step_group[r]
                    srng = lay.step_full_ranges[g]
                    K_g = length(prob.supports[g])
                    pv = view(pbuf, 1:K_g)
                    steps_v = view(full, srng)
                    ld = _row_probs!(pv, eta, steps_v)
                    yk = prob.score_k[r]
                    cum_obs = yk == 0 ? 0.0 : sum(view(steps_v, 1:yk))
                    s_ll += prob.weights[r] * ((yk * eta - cum_obs) - ld)
                end
                lls[q] = s_ll + log_w[q]
            end
            mval = maximum(lls)
            pw = [isfinite(v) ? exp(v - mval) : 0.0 for v in lls]
            pw ./= sum(pw)
            ev = sum(theta_grid[q] * pw[q] for q in 1:Q)
            sv = sqrt(max(sum((theta_grid[q] - ev)^2 * pw[q] for q in 1:Q), 0.0))
            qs = _weighted_quantiles(theta_grid, pw)
            eap_vals[p] = ev
            eap_sds[p] = sv
            eap_q05[p], eap_q50[p], eap_q95[p] = qs[1], qs[2], qs[3]
        end
    end

    rows_out = NamedTuple[]
    primary_theta = zeros(Float64, P)
    for p in 1:P
        rs = p_rows[p]
        st = lay.extreme_person_status[p]
        raw_tot = sum(prob.weights[r] * prob.raw_score[r] for r in rs)
        min_tot = sum(prob.weights[r] * first(prob.supports[prob.step_group[r]]) for r in rs)
        max_tot = sum(prob.weights[r] * last(prob.supports[prob.step_group[r]]) for r in rs)
        w_n = sum(prob.weights[r] for r in rs)

        wle_sol = _solve_person_root(rs, base_eta, full, prob, lay; weighted = true)
        mle_sol = st in (:all_minimum, :all_maximum) ?
            (; estimate = st === :all_minimum ? -Inf : Inf, se = NaN, residual = 0.0, converged = false) :
            _solve_person_root(rs, base_eta, full, prob, lay; weighted = false)

        if prob.method === :jmle
            if st === :anchored
                est_p = prob.person_anchors[p]
                se_p = missing
                cse_p = missing
                fin_p = true
                primary_theta[p] = est_p
            elseif st in (:all_minimum, :all_maximum) && extreme_adjustment == 0.0
                est_p = st === :all_minimum ? -Inf : Inf
                se_p = missing
                cse_p = missing
                fin_p = false
                primary_theta[p] = est_p
            elseif st in (:all_minimum, :all_maximum) && extreme_adjustment > 0.0
                est_p = full[lay.person_full_range[p]]
                ev_p = _eval_person_theta(est_p, rs, base_eta, full, prob, lay; weighted = false)
                hse = jmle_full_se === nothing ? NaN : jmle_full_se[lay.person_full_range[p]]
                se_p = isfinite(hse) ? hse : missing
                cse_p = ev_p.info > 0 ? 1.0 / sqrt(ev_p.info) : missing
                fin_p = isfinite(est_p)
                primary_theta[p] = est_p
            else
                est_p = full[lay.person_full_range[p]]
                ev_p = _eval_person_theta(est_p, rs, base_eta, full, prob, lay; weighted = false)
                hse = jmle_full_se === nothing ? NaN : jmle_full_se[lay.person_full_range[p]]
                se_p = isfinite(hse) ? hse : missing
                cse_p = ev_p.info > 0 ? 1.0 / sqrt(ev_p.info) : missing
                fin_p = true
                primary_theta[p] = est_p
            end
            push!(rows_out, (;
                person = prob.person_levels[p],
                n_ratings = length(rs),
                weighted_n = w_n,
                raw_score = raw_tot,
                min_possible = min_tot,
                max_possible = max_tot,
                extreme = st,
                finite_mle = fin_p,
                estimate = fin_p ? est_p : missing,
                limit_estimate = est_p,
                se = se_p,
                conditional_se = cse_p,
                wle = isfinite(wle_sol.estimate) ? wle_sol.estimate : missing,
                wle_se = isfinite(wle_sol.se) ? wle_sol.se : missing,
                uncertainty_basis = st === :anchored ? :fixed_anchor : (!fin_p ? :no_finite_jmle : :constrained_observed_information),
            ))
        else
            primary_theta[p] = eap_vals[p]
            push!(rows_out, (;
                person = prob.person_levels[p],
                n_ratings = length(rs),
                weighted_n = w_n,
                raw_score = raw_tot,
                min_possible = min_tot,
                max_possible = max_tot,
                extreme = st,
                finite_mle = !(st in (:all_minimum, :all_maximum)) && isfinite(mle_sol.estimate),
                estimate = eap_vals[p],
                eap = eap_vals[p],
                eap_sd = eap_sds[p],
                eap_q05 = eap_q05[p],
                eap_q50 = eap_q50[p],
                eap_q95 = eap_q95[p],
                se = eap_sds[p], # posterior SD for EAP row compatibility, tagged explicitly
                wle = isfinite(wle_sol.estimate) ? wle_sol.estimate : missing,
                wle_se = isfinite(wle_sol.se) ? wle_sol.se : missing,
                mle = !(st in (:all_minimum, :all_maximum)) && isfinite(mle_sol.estimate) ? mle_sol.estimate : missing,
                mle_se = !(st in (:all_minimum, :all_maximum)) && isfinite(mle_sol.se) ? mle_sol.se : missing,
                uncertainty_basis = :empirical_bayes_quadrature_posterior_sd,
            ))
        end
    end
    return (; rows = rows_out, primary_theta)
end

# ---------------------------------------------------------------------------
# 7. Response Residuals, Wright-Masters Fit Diagnostics & Reliability
# ---------------------------------------------------------------------------

@inline function _wilson_hilferty_zstd(mnsq::Float64, df::Float64;
        cap::Union{Nothing,Float64} = 9.0, whexact::Bool = true)
    (isfinite(mnsq) && mnsq >= 0.0 && isfinite(df) && df > 0.0) || return missing
    q = sqrt(2.0 / df)
    z = 3.0 * (cbrt(mnsq) - 1.0) / q + (whexact ? q / 3.0 : 0.0)
    isfinite(z) || return missing
    cap === nothing && return z
    return clamp(z, -cap, cap)
end

function _summarize_fit_rows(indices::Vector{Int}, obs_var::Vector{Float64}, obs_m4::Vector{Float64},
        obs_z2::Vector{Float64}, obs_bzero::BitVector, weights::Vector{Float64};
        has_boundary_proxy::Bool = false, single_obs_free_jmle::Bool = false,
        zstd_cap::Union{Nothing,Float64} = 9.0, whexact::Bool = true)
    if isempty(indices) || single_obs_free_jmle
        return (; n_rows = length(indices), weighted_n = isempty(indices) ? 0.0 : sum(weights[r] for r in indices),
            infit = missing, outfit = missing, infit_zstd = missing, outfit_zstd = missing,
            df_infit = missing, df_outfit = missing,
            infit_zstd_engine = missing, outfit_zstd_engine = missing,
            df_infit_engine = missing, df_outfit_engine = missing,
            status = single_obs_free_jmle ? :unavailable_zero_df : :unavailable)
    end
    sum_w = 0.0
    sum_vw = 0.0
    sum_z2_vw = 0.0
    sum_z2_w = 0.0
    denom_infit = 0.0
    denom_outfit = 0.0
    n_unavail = 0
    for r in indices
        w = weights[r]
        sum_w += w
        if obs_bzero[r]
            # Exact +/-Inf person boundary row: E = y, Var = 0, z^2 * Var = 0
            continue
        end
        v = obs_var[r]
        z2 = obs_z2[r]
        m4 = obs_m4[r]
        if !(isfinite(v) && v > 1e-10 && isfinite(z2) && isfinite(m4))
            n_unavail += 1
            continue
        end
        sum_vw += w * v
        sum_z2_vw += w * z2 * v
        sum_z2_w += w * z2
        denom_infit += w * (m4 - v^2)
        denom_outfit += w * (m4 / (v^2) - 1.0)
    end
    if n_unavail > 0 || sum_vw <= 1e-10 || sum_w <= 0.0
        return (; n_rows = length(indices), weighted_n = sum_w,
            infit = missing, outfit = missing, infit_zstd = missing, outfit_zstd = missing,
            df_infit = missing, df_outfit = missing,
            infit_zstd_engine = missing, outfit_zstd_engine = missing,
            df_infit_engine = missing, df_outfit_engine = missing,
            status = :unavailable)
    end
    infit = sum_z2_vw / sum_vw
    outfit = sum_z2_w / sum_w
    df_inf_fac = denom_infit > 1e-12 ? 2.0 * (sum_vw^2) / denom_infit : NaN
    df_out_fac = denom_outfit > 1e-12 ? 2.0 * (sum_w^2) / denom_outfit : NaN
    df_inf_eng = sum_vw
    df_out_eng = sum_w

    iz_fac = has_boundary_proxy ? missing : _wilson_hilferty_zstd(infit, df_inf_fac; cap = zstd_cap, whexact)
    oz_fac = has_boundary_proxy ? missing : _wilson_hilferty_zstd(outfit, df_out_fac; cap = zstd_cap, whexact)
    iz_eng = has_boundary_proxy ? missing : _wilson_hilferty_zstd(infit, df_inf_eng; cap = nothing, whexact)
    oz_eng = has_boundary_proxy ? missing : _wilson_hilferty_zstd(outfit, df_out_eng; cap = nothing, whexact)
    st = has_boundary_proxy ? :zstd_withheld_extreme_person_boundary :
         (ismissing(iz_fac) || ismissing(oz_fac) ? :zstd_unavailable_low_df : :available_descriptive)
    return (;
        n_rows = length(indices),
        weighted_n = sum_w,
        infit,
        outfit,
        infit_zstd = iz_fac,
        outfit_zstd = oz_fac,
        df_infit = isfinite(df_inf_fac) ? df_inf_fac : missing,
        df_outfit = isfinite(df_out_fac) ? df_out_fac : missing,
        infit_zstd_engine = iz_eng,
        outfit_zstd_engine = oz_eng,
        df_infit_engine = df_inf_eng,
        df_outfit_engine = df_out_eng,
        status = st,
    )
end

function _ptmea_corr(scores::AbstractVector{<:Real}, measures::AbstractVector{<:Real})
    length(scores) >= 2 || return missing
    ok = [isfinite(scores[i]) && isfinite(measures[i]) for i in eachindex(scores)]
    count(ok) >= 2 || return missing
    sx = Float64[scores[i] for i in eachindex(scores) if ok[i]]
    mx = Float64[measures[i] for i in eachindex(measures) if ok[i]]
    (std(sx) > 1e-12 && std(mx) > 1e-12) || return missing
    return cor(sx, mx)
end

@inline _finite_pos_num(x) = !(x === missing) && x isa Real && isfinite(x) && Float64(x) > 0.0
@inline _finite_num(x) = !(x === missing) && x isa Real && isfinite(x)

@inline function _sep_rel_strata_stats(mv::Float64, ev::Float64; is_eap::Bool = false)
    sig = is_eap ? mv : max(mv - ev, 0.0)
    sep = ev > 0.0 ? sqrt(sig / ev) : missing
    rel = is_eap ? (mv + ev > 0.0 ? mv / (mv + ev) : 0.0) : (mv > 0.0 ? sig / mv : missing)
    str = sep === missing ? missing : (4.0 * sep + 1.0) / 3.0
    return (; sd = sqrt(max(mv, 0.0)), rmse = sqrt(max(ev, 0.0)), true_sd = sqrt(sig),
        separation = sep, strata = str, reliability = rel)
end

function _unavailable_reliability_row(
        facet::Symbol, n_levels::Int, n_valid::Int;
        basis::Symbol, status::Symbol,
        variance_definition::Symbol = :sample,
        se_definition::Symbol = :not_applicable,
        extreme_policy::Symbol = :not_applicable)
    return (;
        facet,
        n_levels,
        n_valid,
        sd = missing,
        rmse = missing,
        true_sd = missing,
        separation = missing,
        strata = missing,
        reliability = missing,
        basis,
        status,
        variance_definition,
        se_definition,
        extreme_policy,
        population_sd = missing,
        population_separation = missing,
        population_strata = missing,
        population_reliability = missing,
        real_rmse = missing,
        real_separation = missing,
        real_strata = missing,
        real_reliability = missing,
        facets_conditional_rmse = missing,
        facets_conditional_separation = missing,
        facets_conditional_strata = missing,
        facets_conditional_reliability = missing,
    )
end

function _frequentist_person_reliability_row(
        person_rows::AbstractVector{<:NamedTuple};
        is_eap::Bool,
        grouped::Bool = false,
        extreme_adjusted::Bool = false,
        variance::Symbol = :sample,
        se::Symbol = :default,
        nonextreme_only::Bool = false)
    variance in (:sample, :population) ||
        throw(ArgumentError("variance must be :sample or :population; got $(repr(variance))"))
    se in (:default, :observed, :conditional, :real) ||
        throw(ArgumentError("se must be :default, :observed, :conditional, or :real; got $(repr(se))"))

    ext_policy = nonextreme_only ? :excluded_extremes :
        (is_eap ? :all_finite_included : (extreme_adjusted ? :included_adjusted : :withhold_if_any_nonfinite))
    cand_rows = nonextreme_only ?
        [r for r in person_rows if !(get(r, :extreme, :interior) in (:all_minimum, :all_maximum))] :
        collect(person_rows)

    _eap_sd_of(r) = hasproperty(r, :eap_sd) && !(r.eap_sd === missing) ? r.eap_sd : get(r, :posterior_sd, missing)
    _model_se_of(r) = is_eap ? _eap_sd_of(r) :
        (se === :observed ? get(r, :se, missing) : get(r, :conditional_se, missing))

    if is_eap && se === :conditional
        return _unavailable_reliability_row(
            :person, length(person_rows), length(cand_rows);
            basis = :not_applicable_conditional_se_on_shrunk_eap,
            status = :not_applicable,
            variance_definition = variance,
            se_definition = :model_conditional,
            extreme_policy = ext_policy,
        )
    end

    req_se_of(r) = se === :real ? get(r, :real_se, missing) : _model_se_of(r)
    se_def = se === :real ? (is_eap ? :real_eap_posterior_sd : :real_conditional) :
        (is_eap ? :model_eap_posterior_sd : (se === :observed ? :model_observed_information : :model_conditional))
    basis_sym = is_eap ?
        (grouped ? :pooled_grouped_eap_posterior_sd_total_variance : :eap_posterior_sd_total_variance) :
        (se === :observed ? :observed_information_se_variance_correction :
         se === :real ? :real_conditional_se_variance_correction : :conditional_se_variance_correction)

    valid_p = [r for r in cand_rows if !Bool(get(r, :fixed, false)) && _finite_num(r.estimate) && _finite_pos_num(req_se_of(r))]
    target_n = nonextreme_only ? length(cand_rows) : length(person_rows)
    if !(length(valid_p) == target_n && length(valid_p) >= 2)
        return _unavailable_reliability_row(
            :person, length(person_rows), length(valid_p);
            basis = basis_sym,
            status = :withheld_incomplete_or_extreme_levels,
            variance_definition = variance,
            se_definition = se_def,
            extreme_policy = ext_policy,
        )
    end

    ests = Float64[Float64(r.estimate) for r in valid_p]
    ses_req = Float64[Float64(req_se_of(r)) for r in valid_p]
    mv_samp = var(ests; corrected = true)
    mv_pop = var(ests; corrected = false)
    mv_main = variance === :population ? mv_pop : mv_samp
    ev_req = mean(ses_req .^ 2)
    main_st = _sep_rel_strata_stats(mv_main, ev_req; is_eap)

    def_ok = all(r -> _finite_pos_num(_model_se_of(r)), valid_p)
    ev_def = def_ok ? mean(Float64(_model_se_of(r))^2 for r in valid_p) : NaN
    pop_st = isfinite(ev_def) ? _sep_rel_strata_stats(mv_pop, ev_def; is_eap) :
        (; sd = missing, separation = missing, strata = missing, reliability = missing)

    real_ok = all(r -> _finite_pos_num(get(r, :real_se, missing)), valid_p)
    real_st = real_ok ? _sep_rel_strata_stats(variance === :population ? mv_pop : mv_samp,
        mean(Float64(r.real_se)^2 for r in valid_p); is_eap) :
        (; rmse = missing, separation = missing, strata = missing, reliability = missing)

    cond_ok = !is_eap && all(r -> _finite_pos_num(get(r, :conditional_se, missing)), valid_p)
    cond_st = cond_ok ? _sep_rel_strata_stats(variance === :population ? mv_pop : mv_samp,
        mean(Float64(r.conditional_se)^2 for r in valid_p); is_eap = false) :
        (; rmse = missing, separation = missing, strata = missing, reliability = missing)

    return (;
        facet = :person,
        n_levels = length(person_rows),
        n_valid = length(valid_p),
        sd = main_st.sd,
        rmse = main_st.rmse,
        true_sd = main_st.true_sd,
        separation = main_st.separation,
        strata = main_st.strata,
        reliability = main_st.reliability,
        basis = basis_sym,
        status = :available_descriptive,
        variance_definition = variance,
        se_definition = se_def,
        extreme_policy = ext_policy,
        population_sd = pop_st.sd,
        population_separation = pop_st.separation,
        population_strata = pop_st.strata,
        population_reliability = pop_st.reliability,
        real_rmse = real_st.rmse,
        real_separation = real_st.separation,
        real_strata = real_st.strata,
        real_reliability = real_st.reliability,
        facets_conditional_rmse = cond_st.rmse,
        facets_conditional_separation = cond_st.separation,
        facets_conditional_strata = cond_st.strata,
        facets_conditional_reliability = cond_st.reliability,
    )
end

function _frequentist_facet_reliability_row(
        fname::Symbol,
        frows::AbstractVector{<:NamedTuple};
        method::Symbol = :mmle,
        variance::Symbol = :sample,
        se::Symbol = :default,
        nonextreme_only::Bool = false,
        extreme_levels = NamedTuple[])
    variance in (:sample, :population) ||
        throw(ArgumentError("variance must be :sample or :population; got $(repr(variance))"))
    se in (:default, :observed, :conditional, :real) ||
        throw(ArgumentError("se must be :default, :observed, :conditional, or :real; got $(repr(se))"))

    ext_set = Set(x.level for x in extreme_levels if get(x, :facet, nothing) === fname)
    cand_rows = (nonextreme_only && !isempty(ext_set)) ?
        [r for r in frows if !(r.level in ext_set)] : collect(frows)
    ext_policy = nonextreme_only ? :excluded_extremes : :all_finite_included

    all_free_finite = length(cand_rows) >= 2 &&
        all(r -> !Bool(r.fixed) && _finite_num(r.estimate), cand_rows)
    obs_ok = all_free_finite && all(r -> _finite_pos_num(get(r, :se, missing)), cand_rows)
    cond_ok = all_free_finite && all(r -> _finite_pos_num(get(r, :conditional_se, missing)), cand_rows)
    real_ok = all_free_finite && all(r -> _finite_pos_num(get(r, :real_se, missing)), cand_rows)

    def_mode = obs_ok ? :observed : (cond_ok ? :conditional : :none)
    chosen_mode = se === :default ? def_mode :
                  se === :observed ? (obs_ok ? :observed : :none) :
                  se === :conditional ? (cond_ok ? :conditional : :none) :
                  (real_ok ? :real : :none)

    if chosen_mode === :none
        return _unavailable_reliability_row(
            fname, length(frows), count(r -> !Bool(r.fixed), cand_rows);
            basis = :unassessable_fixed_or_missing_se,
            status = :unassessable,
            variance_definition = variance,
            se_definition = :not_applicable,
            extreme_policy = ext_policy,
        )
    end

    ests = Float64[Float64(r.estimate) for r in cand_rows]
    mv_samp = var(ests; corrected = true)
    mv_pop = var(ests; corrected = false)
    mv_main = variance === :population ? mv_pop : mv_samp

    ses_real = real_ok ? Float64[Float64(r.real_se) for r in cand_rows] : Float64[]

    ses_main = chosen_mode === :observed ? Float64[Float64(r.se) for r in cand_rows] :
               chosen_mode === :conditional ? Float64[Float64(r.conditional_se) for r in cand_rows] : ses_real
    ev_main = mean(ses_main .^ 2)
    main_st = _sep_rel_strata_stats(mv_main, ev_main; is_eap = false)

    pop_st = def_mode !== :none ?
        _sep_rel_strata_stats(
            mv_pop,
            mean((def_mode === :observed ? Float64(r.se) : Float64(r.conditional_se))^2 for r in cand_rows);
            is_eap = false,
        ) :
        (; sd = missing, separation = missing, strata = missing, reliability = missing)

    real_st = real_ok ? _sep_rel_strata_stats(mv_main, mean(ses_real .^ 2); is_eap = false) :
        (; rmse = missing, separation = missing, strata = missing, reliability = missing)
    cond_st = cond_ok ? _sep_rel_strata_stats(mv_main, mean(Float64(r.conditional_se)^2 for r in cand_rows); is_eap = false) :
        (; rmse = missing, separation = missing, strata = missing, reliability = missing)

    se_def = chosen_mode === :observed ? :model_observed_information :
             chosen_mode === :conditional ? :model_conditional :
             (method === :jmle ? :real_conditional : :real_observed_information)
    basis_sym = chosen_mode === :observed ? :observed_information_se_variance_correction :
                chosen_mode === :conditional ? :conditional_se_variance_correction :
                (method === :jmle ? :real_conditional_se_variance_correction : :real_observed_information_se_variance_correction)

    return (;
        facet = fname,
        n_levels = length(frows),
        n_valid = length(cand_rows),
        sd = main_st.sd,
        rmse = main_st.rmse,
        true_sd = main_st.true_sd,
        separation = main_st.separation,
        strata = main_st.strata,
        reliability = main_st.reliability,
        basis = basis_sym,
        status = :available_descriptive,
        variance_definition = variance,
        se_definition = se_def,
        extreme_policy = ext_policy,
        population_sd = pop_st.sd,
        population_separation = pop_st.separation,
        population_strata = pop_st.strata,
        population_reliability = pop_st.reliability,
        real_rmse = real_st.rmse,
        real_separation = real_st.separation,
        real_strata = real_st.strata,
        real_reliability = real_st.reliability,
        facets_conditional_rmse = cond_st.rmse,
        facets_conditional_separation = cond_st.separation,
        facets_conditional_strata = cond_st.strata,
        facets_conditional_reliability = cond_st.reliability,
    )
end

function compute_diagnostics_and_tables(full::Vector{Float64}, primary_theta::Vector{Float64},
        person_rows_info::AbstractVector{<:NamedTuple}, full_se::Vector{Float64}, prob::Problem, lay::Layout;
        interval::Float64 = 0.95, zstd_cap::Union{Nothing,Float64} = 9.0, whexact::Bool = true)
    n = prob.n_obs
    obs_exp = zeros(Float64, n)
    obs_var = zeros(Float64, n)
    obs_m4 = zeros(Float64, n)
    obs_z2 = fill(NaN, n)
    obs_bzero = falses(n)
    obs_eta = zeros(Float64, n)
    K_max = maximum(length, prob.supports)
    pbuf = zeros(Float64, K_max)

    for r in 1:n
        p = prob.person_idx[r]
        th = primary_theta[p]
        g = prob.step_group[r]
        K_g = length(prob.supports[g])
        yk = prob.score_k[r]
        if !isfinite(th)
            # +/-Inf boundary person in unadjusted JMLE
            obs_eta[r] = th
            obs_exp[r] = th < 0 ? 0.0 : Float64(K_g - 1)
            obs_var[r] = 0.0
            obs_m4[r] = 0.0
            obs_z2[r] = 0.0
            obs_bzero[r] = true
        else
            eta = th
            for (fi, f) in enumerate(prob.facets)
                eta += f.sign * full[lay.facet_full_ranges[fi][f.index[r]]]
            end
            obs_eta[r] = eta
            srng = lay.step_full_ranges[g]
            pv = view(pbuf, 1:K_g)
            _row_probs!(pv, eta, view(full, srng))
            ek = 0.0
            for k in 1:(K_g - 1)
                ek += k * pv[k + 1]
            end
            vk = 0.0
            m4k = 0.0
            for k in 0:(K_g - 1)
                d = k - ek
                d2 = d * d
                vk += pv[k + 1] * d2
                m4k += pv[k + 1] * d2 * d2
            end
            obs_exp[r] = ek
            obs_var[r] = vk
            obs_m4[r] = m4k
            obs_z2[r] = vk > 1e-10 ? (yk - ek)^2 / vk : NaN
        end
    end

    z_crit = quantile(Normal(), 0.5 * (1.0 + interval))
    overall_fit = merge(
        _summarize_fit_rows(collect(1:n), obs_var, obs_m4, obs_z2, obs_bzero, prob.weights;
            has_boundary_proxy = any(obs_bzero), zstd_cap, whexact),
        (; whexact, zstd_cap),
    )

    # Precompute FACETS-style marginal Fair(M) and Fair(Z) baselines across step groups
    same_sup_fa = allequal(prob.supports)
    fin_th_fa = Float64[th for th in primary_theta if isfinite(th)]
    th_bar_fa = isempty(fin_th_fa) ? 0.0 : mean(fin_th_fa)
    f_means_fa = Float64[mean(view(full, lay.facet_full_ranges[fi])) for fi in eachindex(prob.facets)]
    f_shift_fa = sum(prob.facets[fi].sign * f_means_fa[fi] for fi in eachindex(prob.facets); init = 0.0)
    tau_groups_fa = [Float64[full[idx] for idx in lay.step_full_ranges[g]] for g in eachindex(prob.supports)]
    cat_groups_fa = [Float64.(collect(prob.supports[g])) for g in eachindex(prob.supports)]
    tau_mean_fa = same_sup_fa ?
        Float64[mean(tau_groups_fa[g][h] for g in eachindex(tau_groups_fa)) for h in 1:length(tau_groups_fa[1])] :
        Float64[]

    # Person measure + fit table
    P = length(prob.person_levels)
    p_grp = [Int[] for _ in 1:P]
    for r in 1:n
        push!(p_grp[prob.person_idx[r]], r)
    end
    person_measures = NamedTuple[]
    for p in 1:P
        rs = p_grp[p]
        pr = person_rows_info[p]
        single_free = prob.method === :jmle && !isfinite(prob.person_anchors[p]) && length(rs) == 1
        has_b = any(r -> obs_bzero[r], rs)
        fstat = (!pr.finite_mle && prob.method === :jmle) ?
            (; infit = missing, outfit = missing, infit_zstd = missing, outfit_zstd = missing,
               df_infit = missing, df_outfit = missing, infit_zstd_engine = missing,
               outfit_zstd_engine = missing, df_infit_engine = missing, df_outfit_engine = missing,
               status = :unavailable_extreme_boundary) :
            _summarize_fit_rows(rs, obs_var, obs_m4, obs_z2, obs_bzero, prob.weights;
                has_boundary_proxy = has_b, single_obs_free_jmle = single_free, zstd_cap, whexact)
        info_sum = sum((obs_bzero[r] ? 0.0 : prob.weights[r] * obs_var[r]) for r in rs; init = 0.0)
        cond_se = (prob.method === :jmle && isfinite(prob.person_anchors[p])) || (!pr.finite_mle && prob.method === :jmle) ?
            missing : (info_sum > 0.0 ? 1.0 / sqrt(info_sum) : missing)
        base_se_for_real = prob.method === :mmle ? pr.eap_sd : (cond_se isa Real ? cond_se : NaN)
        real_se = (isfinite(base_se_for_real) && !(fstat.infit === missing)) ?
            base_se_for_real * sqrt(max(1.0, Float64(fstat.infit))) : missing
        est_val = pr.estimate
        se_val = pr.se
        lo = (!(est_val === missing) && !(se_val === missing) && isfinite(se_val)) ? est_val - z_crit * se_val : missing
        hi = (!(est_val === missing) && !(se_val === missing) && isfinite(se_val)) ? est_val + z_crit * se_val : missing
        target_scores = Float64[prob.raw_score[r] for r in rs]
        target_meas = Float64[obs_eta[r] - (isfinite(primary_theta[p]) ? primary_theta[p] : 0.0) for r in rs]
        ptm = _ptmea_corr(target_scores, -target_meas)
        p_fair_m, p_fair_z = if same_sup_fa
            th_p_fa = primary_theta[p]
            fm_p = first(_freq_adjacent_expected_score_and_slope(
                isfinite(th_p_fa) ? (th_p_fa + f_shift_fa) : th_p_fa, tau_mean_fa, cat_groups_fa[1]))
            fz_p = first(_freq_adjacent_expected_score_and_slope(th_p_fa, tau_mean_fa, cat_groups_fa[1]))
            (isfinite(fm_p) ? fm_p : missing, isfinite(fz_p) ? fz_p : missing)
        else
            (missing, missing)
        end

        push!(person_measures, merge(pr, (;
            facet = :person,
            level = prob.person_levels[p],
            fixed = isfinite(prob.person_anchors[p]),
            fair_m = p_fair_m,
            fair_z = p_fair_z,
            conditional_se = cond_se,
            real_se,
            lower = lo,
            upper = hi,
            interval,
            infit = fstat.infit,
            outfit = fstat.outfit,
            infit_zstd = fstat.infit_zstd,
            outfit_zstd = fstat.outfit_zstd,
            df_infit = fstat.df_infit,
            df_outfit = fstat.df_outfit,
            infit_zstd_engine = fstat.infit_zstd_engine,
            outfit_zstd_engine = fstat.outfit_zstd_engine,
            fit_status = fstat.status,
            ptmea = ptm,
        )))
    end

    # Non-person facet measure + fit tables
    facet_measures = NamedTuple[]
    extreme_facet_levels = NamedTuple[]
    for (fi, f) in enumerate(prob.facets)
        L = length(f.levels)
        f_grp = [Int[] for _ in 1:L]
        for r in 1:n
            push!(f_grp[f.index[r]], r)
        end
        for l in 1:L
            rs = f_grp[l]
            idx_full = lay.facet_full_ranges[fi][l]
            is_fix = lay.fixed_mask[idx_full]
            est = full[idx_full]
            hse = full_se[idx_full]
            se_v = (!is_fix && isfinite(hse) && hse > 0.0) ? hse : missing
            info_sum = sum((obs_bzero[r] ? 0.0 : prob.weights[r] * obs_var[r]) for r in rs; init = 0.0)
            cond_se = (!is_fix && info_sum > 0.0) ? 1.0 / sqrt(info_sum) : missing
            has_b = any(r -> obs_bzero[r], rs)
            single_free = prob.method === :jmle && !is_fix && length(rs) == 1
            fstat = _summarize_fit_rows(rs, obs_var, obs_m4, obs_z2, obs_bzero, prob.weights;
                has_boundary_proxy = has_b, single_obs_free_jmle = single_free, zstd_cap, whexact)
            model_se = prob.method === :mmle ? se_v : cond_se
            real_se = (!(model_se === missing) && !(fstat.infit === missing)) ?
                model_se * sqrt(max(1.0, Float64(fstat.infit))) : missing
            lo = !(se_v === missing) ? est - z_crit * se_v : missing
            hi = !(se_v === missing) ? est + z_crit * se_v : missing
            clo = !(cond_se === missing) ? est - z_crit * cond_se : missing
            chi = !(cond_se === missing) ? est + z_crit * cond_se : missing

            # Check score boundary on facet level
            all_min = !isempty(rs) && all(r -> prob.score_k[r] == 0, rs)
            all_max = !isempty(rs) && all(r -> prob.score_k[r] == length(prob.supports[prob.step_group[r]]) - 1, rs)
            if !is_fix && (all_min || all_max)
                push!(extreme_facet_levels, (; facet = f.name, level = f.levels[l],
                    direction = all_min ? :all_minimum : :all_maximum))
            end

            scores_l = Float64[prob.raw_score[r] for r in rs]
            eta_l = Float64[obs_eta[r] for r in rs]
            meas_l = Float64[primary_theta[prob.person_idx[r]] for r in rs]
            ptm = _ptmea_corr(scores_l, eta_l)
            ptm_p = _ptmea_corr(scores_l, meas_l)
            raw_sum = isempty(rs) ? 0.0 : sum(prob.weights[r] * prob.raw_score[r] for r in rs)
            exp_sum = isempty(rs) ? 0.0 : sum(prob.weights[r] * (first(prob.supports[prob.step_group[r]]) + obs_exp[r]) for r in rs)
            f_fair_m, f_fair_z = if same_sup_fa || f.name === prob.step_owner
                c_v_fa = f.name === prob.step_owner ? cat_groups_fa[l] : cat_groups_fa[1]
                t_v_fa = f.name === prob.step_owner ? tau_groups_fa[l] : tau_mean_fa
                oth_sh = f_shift_fa - f.sign * f_means_fa[fi]
                fm_v = first(_freq_adjacent_expected_score_and_slope(th_bar_fa + f.sign * est + oth_sh, t_v_fa, c_v_fa))
                fz_v = first(_freq_adjacent_expected_score_and_slope(f.sign * est, t_v_fa, c_v_fa))
                (isfinite(fm_v) ? fm_v : missing, isfinite(fz_v) ? fz_v : missing)
            else
                (missing, missing)
            end

            push!(facet_measures, (;
                facet = f.name,
                level = f.levels[l],
                n_ratings = length(rs),
                weighted_n = isempty(rs) ? 0.0 : sum(prob.weights[r] for r in rs),
                observed_average = isempty(rs) ? missing : raw_sum / sum(prob.weights[r] for r in rs),
                expected_average = isempty(rs) ? missing : exp_sum / sum(prob.weights[r] for r in rs),
                fair_m = f_fair_m,
                fair_z = f_fair_z,
                fixed = is_fix,
                sign = f.sign,
                estimate = est,
                se = se_v,
                model_se,
                conditional_se = cond_se,
                real_se,
                lower = lo,
                upper = hi,
                conditional_lower = clo,
                conditional_upper = chi,
                interval,
                infit = fstat.infit,
                outfit = fstat.outfit,
                infit_zstd = fstat.infit_zstd,
                outfit_zstd = fstat.outfit_zstd,
                df_infit = fstat.df_infit,
                df_outfit = fstat.df_outfit,
                infit_zstd_engine = fstat.infit_zstd_engine,
                outfit_zstd_engine = fstat.outfit_zstd_engine,
                fit_status = fstat.status,
                ptmea = ptm,
                ptmea_person = ptm_p,
                uncertainty_basis = is_fix ? :fixed_constraint : :constrained_observed_information,
            ))
        end
    end

    # Step threshold table & Category usage table
    step_rows = NamedTuple[]
    category_rows = NamedTuple[]
    for g in eachindex(prob.supports)
        sup = prob.supports[g]
        K_g = length(sup)
        H_g = K_g - 1
        srng = lay.step_full_ranges[g]
        glbl = prob.step_owner === :global ? :Common : prob.step_group_levels[g]
        g_rows = [r for r in 1:n if prob.step_group[r] == g]
        w_tot = isempty(g_rows) ? 0.0 : sum(prob.weights[r] for r in g_rows)

        cat_counts = zeros(Float64, K_g)
        cat_raw_n = zeros(Int, K_g)
        cat_exp = zeros(Float64, K_g)
        cat_th_sum = zeros(Float64, K_g)
        cat_th_n = zeros(Float64, K_g)

        for r in g_rows
            yk = prob.score_k[r]
            w = prob.weights[r]
            cat_counts[yk + 1] += w
            cat_raw_n[yk + 1] += 1
            th = primary_theta[prob.person_idx[r]]
            if isfinite(th)
                cat_th_sum[yk + 1] += w * th
                cat_th_n[yk + 1] += w
                pv = view(pbuf, 1:K_g)
                _row_probs!(pv, obs_eta[r], view(full, srng))
                for k in 1:K_g
                    cat_exp[k] += w * pv[k]
                end
            else
                cat_exp[th < 0 ? 1 : K_g] += w
            end
        end

        for k in 1:K_g
            push!(category_rows, (;
                step_facet = prob.step_owner,
                group = glbl,
                category = sup[k],
                count = cat_raw_n[k],
                weighted_count = cat_counts[k],
                proportion = w_tot > 0 ? cat_counts[k] / w_tot : missing,
                expected_count = cat_exp[k],
                expected_proportion = w_tot > 0 ? cat_exp[k] / w_tot : missing,
                average_person_measure = cat_th_n[k] > 0 ? cat_th_sum[k] / cat_th_n[k] : missing,
            ))
        end

        for s in 1:H_g
            idx_full = srng[s]
            est = full[idx_full]
            is_fix = lay.fixed_mask[idx_full]
            hse = full_se[idx_full]
            se_v = (!is_fix && isfinite(hse) && hse > 0.0) ? hse : missing
            lo = !(se_v === missing) ? est - z_crit * se_v : missing
            hi = !(se_v === missing) ? est + z_crit * se_v : missing
            spacing = s == 1 ? missing : est - full[srng[s - 1]]
            disordered = s == 1 ? false : (est < full[srng[s - 1]])
            push!(step_rows, (;
                step_facet = prob.step_owner,
                group = glbl,
                step = s,
                label = "Step_$s",
                transition = "$(sup[s])->$(sup[s + 1])",
                lower_count = cat_raw_n[s],
                upper_count = cat_raw_n[s + 1],
                fixed = is_fix,
                estimate = est,
                se = se_v,
                lower = lo,
                upper = hi,
                interval,
                spacing,
                disordered,
                uncertainty_basis = is_fix ? :fixed_constraint : :constrained_observed_information,
            ))
        end
    end

    # Reliability & separation by facet (with explicit FACETS Sample/Population & Model/Real/Conditional metadata)
    reliability_rows = NamedTuple[]
    push!(reliability_rows, _frequentist_person_reliability_row(
        person_measures;
        is_eap = prob.method === :mmle,
        grouped = false,
        extreme_adjusted = prob.method === :jmle && lay.active_rows == collect(1:n) &&
            any(s -> s in (:all_minimum, :all_maximum), lay.extreme_person_status),
    ))
    for f in prob.facets
        frows = [r for r in facet_measures if r.facet === f.name]
        push!(reliability_rows, _frequentist_facet_reliability_row(
            f.name, frows; method = prob.method, extreme_levels = extreme_facet_levels,
        ))
    end

    return (;
        overall_fit,
        person_measures,
        facet_measures,
        step_rows,
        category_rows,
        reliability_rows,
        extreme_facet_levels,
        obs_expected = obs_exp,
        obs_variance = obs_var,
        obs_std_sq = obs_z2,
        obs_eta,
    )
end

# ---------------------------------------------------------------------------
# 8. Main `fit` Entrypoint & Persistence / Reporting / Comparison Helpers
# ---------------------------------------------------------------------------

function fit(spec_or_target;
        method::Symbol,
        noncenter_facet::Symbol = :person,
        centering::Symbol = :sum_to_zero,
        positive_facets = Symbol[],
        anchors = NamedTuple(),
        weights = nothing,
        extreme_adjustment::Real = 0.0,
        quad_points::Int = 31,
        quadrature::Symbol = :gauss_hermite,
        theta_lim::Real = 4.0,
        population_sd::Real = 1.0,
        estimate_sd::Bool = false,
        estimate_mean::Bool = false,
        mml_engine::Symbol = :hybrid,
        maxit::Int = 400,
        gtol::Real = 1e-9,
        interval::Real = 0.95,
        zstd_cap::Union{Nothing,Real} = 9.0,
        whexact::Bool = true)
    extreme_adjustment isa Real && !(extreme_adjustment isa Bool) && isfinite(extreme_adjustment) && 0.0 <= extreme_adjustment < 1.0 ||
        throw(ArgumentError("extreme_adjustment must be in [0.0, 1.0); use 0.0 for unadjusted JMLE or 0.3 for FACETS adjustment"))
    0.0 < Float64(interval) < 1.0 || throw(ArgumentError("interval must lie in (0, 1)"))
    gtol_f = Float64(gtol)
    gtol_f > 0.0 && isfinite(gtol_f) || throw(ArgumentError("gtol must be finite and positive"))
    maxit >= 1 || throw(ArgumentError("maxit must be >= 1"))
    zstd_cap === nothing || (zstd_cap isa Real && !(zstd_cap isa Bool) && isfinite(zstd_cap) && Float64(zstd_cap) > 0.0) ||
        throw(ArgumentError("zstd_cap must be nothing or a finite positive real number"))
    cap_f = zstd_cap === nothing ? nothing : Float64(zstd_cap)

    prob = compile_problem(spec_or_target; method, noncenter_facet, centering, positive_facets, anchors, weights)
    if prob.method === :jmle
        (estimate_sd || estimate_mean) &&
            throw(ArgumentError("estimate_sd and estimate_mean apply only to method = :mmle"))
    else
        mml_engine in (:hybrid, :direct, :em) ||
            throw(ArgumentError("mml_engine must be :hybrid, :direct, or :em"))
    end

    lay = build_layout(prob;
        extreme_adjustment = Float64(extreme_adjustment),
        estimate_mean = prob.method === :mmle && estimate_mean,
        estimate_sd = prob.method === :mmle && estimate_sd)

    u0 = initial_free_vector(prob, lay; population_sd)
    pop_se = (; mu_se = missing, sigma_se = missing)
    t_start = time()

    if prob.method === :jmle
        ext_adj = Float64(extreme_adjustment)
        if !prob.person_centered
            fill!(u0, 0.0)
            earned = zeros(length(prob.person_levels))
            remaining = zeros(length(earned))
            for r in lay.active_rows
                p = prob.person_idx[r]
                earned[p] += prob.weights[r] * prob.score_k[r]
                remaining[p] += prob.weights[r] * (length(prob.supports[prob.step_group[r]]) - 1 - prob.score_k[r])
            end
            for (j,p) in zip(lay.person_free_range, lay.interior_persons)
                u0[j] = log((earned[p] + 0.5) / (remaining[p] + 1.0))
            end
        end
        fg_j! = (g,x) -> jmle_nll_and_grad!(g, x, prob, lay; extreme_adjustment=ext_adj)
        function joint_direction(x, g)
            if !prob.person_centered && !isempty(lay.person_free_range)
                block = jmle_exact_hessian_and_schur_cov(x, prob, lay; direction_only=true)
                return _joint_schur_direction(block, g)
            end
            H = Symmetric(ForwardDiff.hessian(z -> fg_j!(nothing, z), x))
            ch = cholesky(H; check=false)
            return issuccess(ch) ? -(ch \ g) : nothing
        end
        opt = _fit_joint_newton(fg_j!, joint_direction, u0; maxit, gtol=gtol_f)
        u_hat, nll, g_final = opt.x, opt.f, opt.g
        nit_total, nfev_total = opt.nit, opt.nfev
        sch = jmle_exact_hessian_and_schur_cov(u_hat, prob, lay)
        full_hat = lay.c_vec .+ lay.J_mat * u_hat
        pscores = compute_person_scores(full_hat, prob, lay;
            jmle_full_se = sch.ok ? sch.full_se : nothing,
            extreme_adjustment = ext_adj)
        mu_hat = missing
        sigma_hat = missing
        quad_used = nothing
        hess_pd = sch.ok
        min_eig = sch.min_eig
        cond_num = sch.cond
        full_se = sch.full_se
        cov_expanded = (sch.ok && hasproperty(sch, :cov_np_full)) ? (; kind = :non_person_subspace, offset = sch.np_offset, matrix = sch.cov_np_full) :
                       (sch.ok && hasproperty(sch, :cov_full)) ? (; kind = :full, offset = 0, matrix = sch.cov_full) : nothing
        if ext_adj > 0.0
            nll = jmle_nll_and_grad!(nothing, u_hat, prob, lay; extreme_adjustment = 0.0)
        end
    else
        base_quad = build_quadrature(quadrature, quad_points; sd = 1.0, theta_lim)
        fsd = Float64(population_sd)
        mmle_sc = _build_freq_mmle_scratch(prob, lay, base_quad)
        nf_mml = lay.n_free
        u_start = copy(u0)
        em_used = 0
        if mml_engine in (:hybrid, :em)
            em_used = mml_engine === :em ? maxit : min(6, max(2, maxit ÷ 10))
            _em_warmstart_mmle!(u_start, prob, lay, base_quad; fixed_sd = fsd, em_iters = em_used, scratch = mmle_sc)
        end
        if mml_engine === :em
            g_em = zeros(Float64, nf_mml)
            f_em = mmle_nll_and_grad!(g_em, u_start, prob, lay, base_quad; fixed_sd = fsd, scratch = mmle_sc)
            u_hat = u_start
            nll = f_em
            g_final = g_em
            nit_total = em_used
            nfev_total = em_used
            dec_val = norm(g_em, Inf)
        else
            lbfgs_gtol = nf_mml <= 2000 ? max(gtol_f, 1e-5) : gtol_f
            opt = _optimize_lbfgs((g, x) -> mmle_nll_and_grad!(g, x, prob, lay, base_quad; fixed_sd = fsd, scratch = mmle_sc), u_start;
                maxit = max(1, maxit - em_used), gtol = lbfgs_gtol)
            pol = _polish_mmle_newton!(copy(opt.x), prob, lay, base_quad;
                fixed_sd = fsd, gtol = min(gtol_f, 1e-11), scratch = mmle_sc)
            u_hat = pol.x
            nll = pol.f
            g_final = pol.g
            nit_total = em_used + opt.nit + pol.steps
            nfev_total = em_used + opt.nfev + pol.steps
            dec_val = pol.dec
        end
        full_hat = lay.c_vec .+ lay.J_mat * u_hat
        mu_hat = lay.mu_free_idx > 0 ? u_hat[lay.mu_free_idx] : 0.0
        sigma_hat = lay.log_sigma_free_idx > 0 ? exp(u_hat[lay.log_sigma_free_idx]) : fsd
        quad_used = build_quadrature(quadrature, quad_points; sd = sigma_hat, theta_lim)

        # Exact observed-information Hessian of marginal NLL in free coordinates
        if nf_mml == 0
            hess_pd = true; min_eig = Inf; cond_num = 1.0
            full_se = fill(NaN, lay.n_full_structural)
            cov_expanded = nothing
            pop_se = (; mu_se = missing, sigma_se = missing)
        else
            H_mml = _ordinal_louis(u_hat, prob, lay, base_quad, fsd, mmle_sc)
            eigs = eigvals(Matrix(H_mml))
            min_eig = minimum(eigs)
            cond_num = min_eig > 0 ? maximum(eigs) / min_eig : Inf
            ch = cholesky(H_mml; check = false)
            hess_pd = issuccess(ch)
            if hess_pd
                cov_free = inv(ch)
                cov_full = Matrix(lay.J_mat * cov_free * transpose(lay.J_mat))
                full_se = [lay.fixed_mask[i] ? NaN : sqrt(max(cov_full[i, i], 0.0)) for i in 1:lay.n_full_structural]
                mu_se = lay.mu_free_idx > 0 ? sqrt(max(cov_free[lay.mu_free_idx, lay.mu_free_idx], 0.0)) : missing
                sig_se = lay.log_sigma_free_idx > 0 ? sigma_hat * sqrt(max(cov_free[lay.log_sigma_free_idx, lay.log_sigma_free_idx], 0.0)) : missing
                cov_expanded = (; kind = :full, offset = 0, matrix = cov_full, cov_free)
                pop_se = (; mu_se, sigma_se = sig_se)
            else
                full_se = fill(NaN, lay.n_full_structural)
                cov_expanded = nothing
                pop_se = (; mu_se = missing, sigma_se = missing)
            end
        end
        pscores = compute_person_scores(full_hat, prob, lay;
            quad = base_quad, mu_hat, sigma_hat)
    end
    elapsed = time() - t_start

    tabs = compute_diagnostics_and_tables(full_hat, pscores.primary_theta, pscores.rows, full_se, prob, lay;
        interval = Float64(interval), zstd_cap = cap_f, whexact = Bool(whexact))

    max_grad = isempty(g_final) ? 0.0 : norm(g_final, Inf)
    converged = isfinite(nll) && max_grad <= max(100.0 * gtol_f, 1e-5)
    stationarity_qualified = converged && (hess_pd === true) && isempty(tabs.extreme_facet_levels)

    ll = -nll
    P_cnt = length(prob.person_levels)
    N_cnt = prob.n_obs
    k_free = lay.n_free
    aic = prob.method === :mmle ? (-2.0 * ll + 2.0 * k_free) : missing
    bic_p = prob.method === :mmle ? (-2.0 * ll + k_free * log(P_cnt)) : missing
    bic_n = prob.method === :mmle ? (-2.0 * ll + k_free * log(N_cnt)) : missing

    warnings = String[]
    if prob.method === :jmle
        push!(warnings, "JMLE estimates incidental person parameters jointly with structural facets/steps; point estimates carry finite-test Neyman-Scott scale expansion and asymptotic Wald SEs do not propagate finite-sample bias.")
        n_ext_p = count(s -> s in (:all_minimum, :all_maximum), lay.extreme_person_status)
        if n_ext_p > 0
            push!(warnings, Float64(extreme_adjustment) == 0.0 ?
                "$n_ext_p extreme-score person(s) have no finite unpenalized JMLE (+/-Inf limit retained; inspect .person_scores for finite WLE)." :
                "$n_ext_p extreme-score person(s) use FACETS score adjustment $(Float64(extreme_adjustment)).")
        end
    else
        push!(warnings, "MMLE integrates person abilities over a normal quadrature distribution; person EAP scores are conditional empirical-Bayes summaries that do not propagate calibration uncertainty.")
        if estimate_sd
            push!(warnings, "Population SD was estimated jointly on a finite $(quad_points)-point $(quadrature) grid; inspect quadrature sensitivity on sharp response profiles.")
        end
    end
    if !isempty(tabs.extreme_facet_levels)
        push!(warnings, "$(length(tabs.extreme_facet_levels)) free non-person facet level(s) have all-minimum or all-maximum scores; stationarity qualification is withheld.")
    end

    summary_nt = (;
        inference_paradigm = :frequentist,
        is_bayesian_posterior = false,
        source_kind = prob.source_kind,
        model = prob.model,
        method = prob.method,
        n_observations = N_cnt,
        n_persons = P_cnt,
        n_facets = length(prob.facets),
        facet_names = [f.name for f in prob.facets],
        step_owner = prob.step_owner,
        noncenter_facet = prob.noncenter_facet,
        centering = prob.centering,
        n_free_parameters = k_free,
        loglikelihood = ll,
        deviance = -2.0 * ll,
        aic,
        bic_persons = bic_p,
        bic_observations = bic_n,
        converged,
        stationarity_qualified,
        max_abs_gradient = max_grad,
        hessian_positive_definite = hess_pd,
        min_hessian_eigenvalue = min_eig,
        hessian_condition_number = cond_num,
        n_iterations = nit_total,
        n_evaluations = nfev_total,
        elapsed_seconds = elapsed,
        extreme_adjustment = prob.method === :jmle ? Float64(extreme_adjustment) : missing,
        quadrature = prob.method === :mmle ? quadrature : missing,
        quad_points = prob.method === :mmle ? quad_points : missing,
        theta_lim = prob.method === :mmle ? Float64(theta_lim) : missing,
        population_mean = prob.method === :mmle ? mu_hat : missing,
        population_sd = prob.method === :mmle ? sigma_hat : missing,
        population_mean_se = prob.method === :mmle ? pop_se.mu_se : missing,
        population_sd_se = prob.method === :mmle ? pop_se.sigma_se : missing,
        estimate_mean = prob.method === :mmle ? estimate_mean : false,
        estimate_sd = prob.method === :mmle ? estimate_sd : false,
        mml_engine = prob.method === :mmle ? mml_engine : missing,
        observation_binding = prob.observation_binding,
    )

    core_body = (;
        schema = FIT_SCHEMA,
        summary = summary_nt,
        problem = prob,
        layout = lay,
        u_free = u_hat,
        full_parameters = full_hat,
        gradient = g_final,
        full_se,
        covariance = cov_expanded,
        overall_fit = merge(tabs.overall_fit, (; loglikelihood = ll, deviance = -2.0 * ll, n_free_parameters = k_free)),
        person_scores = tabs.person_measures,
        facet_measures = tabs.facet_measures,
        step_measures = tabs.step_rows,
        category_usage = tabs.category_rows,
        reliability = tabs.reliability_rows,
        extreme_facet_levels = tabs.extreme_facet_levels,
        warnings,
    )
    digest = B._cache_hash((;
        schema = FIT_SCHEMA,
        observation_binding = prob.observation_binding,
        method = prob.method,
        model = prob.model,
        u_free = u_hat,
        loglikelihood = ll,
    ))
    return Fit(merge(core_body, (; content_hash = digest)))
end

function _frequentist_fit_digest(r)
    body = (; schema=FIT_SCHEMA, observation_binding=r.problem.observation_binding,
        method=r.problem.method, model=r.problem.model, u_free=r.u_free, loglikelihood=r.summary.loglikelihood)
    if hasproperty(r.summary,:population)
        body = merge(body,(;population=r.summary.population))
    end
    if hasproperty(r.summary,:calibration)
        body = merge(body,(;calibration=r.summary.calibration,population_mean_se=r.summary.population_mean_se))
    elseif hasproperty(get(r.summary,:fixed_calibration,(;)),:groups) ||
           hasproperty(get(r.summary,:fixed_calibration,(;)),:interaction_dimensions)
        body = merge(body,(;fixed_calibration=r.summary.fixed_calibration))
    end
    return B._cache_hash(body)
end

function checked(f::Fit)
    r = f.record
    r.schema == FIT_SCHEMA || throw(ArgumentError("unknown FrequentistMFRM fit schema"))
    expected = _frequentist_fit_digest(r)
    expected == r.content_hash || throw(ArgumentError("FrequentistMFRM fit checksum mismatch"))
    return r
end

function diagnostics(f::Fit)
    r = checked(f)
    s = r.summary
    return (;
        inference_paradigm = :frequentist,
        is_mcmc = false,
        method = s.method,
        model = s.model,
        converged = s.converged,
        qualified = s.stationarity_qualified,
        qualification_scope = :frequentist_numerical_stationarity,
        max_abs_gradient = s.max_abs_gradient,
        hessian_positive_definite = s.hessian_positive_definite,
        min_hessian_eigenvalue = s.min_hessian_eigenvalue,
        hessian_condition_number = s.hessian_condition_number,
        n_iterations = s.n_iterations,
        n_evaluations = s.n_evaluations,
        n_extreme_persons = count(x -> x.extreme in (:all_minimum, :all_maximum), r.person_scores),
        extreme_facet_levels = r.extreme_facet_levels,
        overall_fit = r.overall_fit,
        warnings = copy(r.warnings),
    )
end

function qualify(f::Fit; max_gradient::Real = 1e-5, max_condition::Real = 1e10)
    d = diagnostics(f)
    grad_ok = isfinite(d.max_abs_gradient) && d.max_abs_gradient <= Float64(max_gradient)
    hess_ok = d.hessian_positive_definite === true && isfinite(d.hessian_condition_number) &&
              d.hessian_condition_number <= Float64(max_condition)
    b_ok = !any(x -> !get(x, :fixed, false), d.extreme_facet_levels)
    ok = d.converged && grad_ok && hess_ok && b_ok
    return merge(d, (;
        qualified = ok,
        gradient_gate_passed = grad_ok,
        hessian_gate_passed = hess_ok,
        boundary_gate_passed = b_ok,
        thresholds = (; max_gradient = Float64(max_gradient), max_condition = Float64(max_condition)),
    ))
end

function report(f::Fit)
    r = checked(f)
    clean_num(x) = x isa AbstractFloat && !isfinite(x) ? string(x) : x
    sanitize_nt(nt::NamedTuple) = (; (k => clean_num(getproperty(nt, k)) for k in keys(nt))...)
    body = (;
        schema = REPORT_SCHEMA,
        source_content_hash = r.content_hash,
        summary = sanitize_nt(r.summary),
        overall_fit = sanitize_nt(r.overall_fit),
        facet_measures = [sanitize_nt(x) for x in r.facet_measures],
        step_measures = [sanitize_nt(x) for x in r.step_measures],
        person_scores = [sanitize_nt(x) for x in r.person_scores],
        category_usage = [sanitize_nt(x) for x in r.category_usage],
        reliability = [sanitize_nt(x) for x in r.reliability],
        warnings = copy(r.warnings),
    )
    return merge(body, (; report_hash = B._cache_hash(body)))
end

@inline function _freq_adjacent_expected_score_and_slope(
        eta::Float64,
        steps_vec::AbstractVector{<:Real},
        cat_vals::AbstractVector{<:Real})
    M = length(cat_vals)
    H = length(steps_vec)
    H == M - 1 || throw(DimensionMismatch("steps_vec length ($H) must equal length(cat_vals) - 1 ($(M - 1))"))
    if !isfinite(eta)
        return eta == Inf ? (Float64(cat_vals[end]), 0.0) :
               eta == -Inf ? (Float64(cat_vals[1]), 0.0) : (NaN, NaN)
    end
    mmax = 0.0
    csum = 0.0
    for lk in 2:M
        csum += Float64(steps_vec[lk - 1])
        v = Float64(lk - 1) * eta - csum
        v > mmax && (mmax = v)
    end
    wsum = exp(-mmax)
    esum = Float64(cat_vals[1]) * wsum
    csum = 0.0
    for lk in 2:M
        csum += Float64(steps_vec[lk - 1])
        v = Float64(lk - 1) * eta - csum
        w = exp(v - mmax)
        wsum += w
        esum += Float64(cat_vals[lk]) * w
    end
    e_val = esum / wsum
    slope = (Float64(cat_vals[1]) - e_val) * 0.0
    csum = 0.0
    for lk in 2:M
        csum += Float64(steps_vec[lk - 1])
        v = Float64(lk - 1) * eta - csum
        pk = exp(v - mmax) / wsum
        slope += pk * (Float64(cat_vals[lk]) - e_val) * Float64(lk - 1)
    end
    return e_val, slope
end

function criteria_report(f::Fit)
    r = checked(f)
    s = r.summary
    return (;
        inference_paradigm = :frequentist,
        method = s.method,
        model = s.model,
        observation_binding = s.observation_binding,
        n_observations = s.n_observations,
        n_persons = s.n_persons,
        n_parameters = s.n_free_parameters,
        loglikelihood = s.loglikelihood,
        deviance = s.deviance,
        aic = s.aic,
        bic_persons = s.bic_persons,
        bic_observations = s.bic_observations,
        quadrature = s.quadrature,
        quad_points = s.quad_points,
        stationarity_qualified = s.stationarity_qualified,
        warning = s.method === :jmle ?
            "AIC/BIC are undefined for JMLE because incidental person parameters grow with N_persons (Neyman-Scott inconsistency); use method = :mmle for marginal likelihood comparison." :
            "Marginal quadrature log-likelihood criteria on the observed rating allocation; match quadrature rules when comparing MMLE models.",
    )
end

function _mmle_row_pattern_system(f::Fit)
    r = f.record
    prob = r.problem
    s = r.summary
    has_pop = hasproperty(s, :population)
    est_mu = Bool(s.estimate_mean)
    est_sd = Bool(s.estimate_sd)
    mu_fix = (est_mu || has_pop) ? 0.0 : Float64(s.population_mean)
    sd_fix = (est_sd || has_pop) ? 1.0 : Float64(s.population_sd)

    if hasproperty(r, :mrcml_operator)
        op = r.mrcml_operator
        U = op.n_patterns
        d_xi = size(op.A_free, 2)
        At = sparse(op.A_free')
        rv = rowvals(At)
        nz = nonzeros(At)
        b_list = Vector{Vector{Float64}}(undef, U)
        c_list = Vector{Vector{Float64}}(undef, U)
        A_list = Vector{Matrix{Float64}}(undef, U)
        for u in 1:U
            rng = op.pattern_ranges[u]
            m0 = first(rng)
            L_u = length(rng) - 1
            bu = Vector{Float64}(undef, L_u)
            cu = Vector{Float64}(undef, L_u)
            Au = zeros(Float64, L_u, d_xi)
            b0 = op.B_pat[m0]
            c0 = op.c_pat[m0]
            for (k, m) in enumerate(rng[2:end])
                bu[k] = op.B_pat[m] - b0
                cu[k] = op.c_pat[m] - c0
                for ptr in nzrange(At, m)
                    Au[k, rv[ptr]] += nz[ptr]
                end
                for ptr in nzrange(At, m0)
                    Au[k, rv[ptr]] -= nz[ptr]
                end
            end
            b_list[u] = bu
            c_list[u] = cu
            A_list[u] = Au
        end
        return (; pat_of_row = op.pattern_of_row, b = b_list, c = c_list, A = A_list, est_mu, est_sd, mu_fix, sd_fix)
    else
        lay = r.layout
        d_xi = lay.n_free - (lay.mu_free_idx > 0 ? 1 : 0) - (lay.log_sigma_free_idx > 0 ? 1 : 0)
        J_struct = d_xi > 0 ? Matrix(lay.J_mat[:, 1:d_xi]) : zeros(Float64, lay.n_full_structural, 0)
        pat_map = Dict{Any,Int}()
        pat_of_row = Vector{Int}(undef, prob.n_obs)
        b_list = Vector{Float64}[]
        c_list = Vector{Float64}[]
        A_list = Matrix{Float64}[]
        for i in 1:prob.n_obs
            g = prob.step_group[i]
            f_idxs = Tuple(fd.index[i] for fd in prob.facets)
            key = (g, f_idxs)
            u = get(pat_map, key, 0)
            if u == 0
                u = length(b_list) + 1
                pat_map[key] = u
                L_u = length(prob.supports[g]) - 1
                srng = lay.step_full_ranges[g]
                c_eta = 0.0
                a_eta = zeros(Float64, d_xi)
                for (fi, fd) in enumerate(prob.facets)
                    row_f = lay.facet_full_ranges[fi][f_idxs[fi]]
                    c_eta += fd.sign * lay.c_vec[row_f]
                    if d_xi > 0
                        @views a_eta .+= fd.sign .* J_struct[row_f, :]
                    end
                end
                bu = Float64[k for k in 1:L_u]
                cu = Vector{Float64}(undef, L_u)
                Au = zeros(Float64, L_u, d_xi)
                cum_c = 0.0
                cum_a = zeros(Float64, d_xi)
                for k in 1:L_u
                    s_row = srng[k]
                    cum_c += lay.c_vec[s_row]
                    if d_xi > 0
                        @views cum_a .+= J_struct[s_row, :]
                    end
                    cu[k] = k * c_eta - cum_c
                    if d_xi > 0
                        @views Au[k, :] .= k .* a_eta .- cum_a
                    end
                end
                push!(b_list, bu)
                push!(c_list, cu)
                push!(A_list, Au)
            end
            pat_of_row[i] = u
        end
        return (; pat_of_row, b = b_list, c = c_list, A = A_list, est_mu, est_sd, mu_fix, sd_fix)
    end
end

function _verify_mmle_nested(f_simple::Fit, f_complex::Fit)
    hp0 = hasproperty(f_simple.record.summary, :population)
    hp1 = hasproperty(f_complex.record.summary, :population)
    if hp0 != hp1
        return (; nested = false, reason = :grouped_population_mismatch, df = 0)
    end
    d0 = Int(f_simple.record.summary.n_free_parameters)
    d1 = Int(f_complex.record.summary.n_free_parameters)
    d1 > d0 || return (; nested = false, reason = :equal_or_larger_parameter_dimension, df = 0)

    sys0 = _mmle_row_pattern_system(f_simple)
    sys1 = _mmle_row_pattern_system(f_complex)
    seen = Set{Tuple{Int,Int}}()
    pairs_u = Tuple{Int,Int}[]
    for i in eachindex(sys0.pat_of_row)
        pr = (sys0.pat_of_row[i], sys1.pat_of_row[i])
        if !(pr in seen)
            push!(seen, pr)
            push!(pairs_u, pr)
        end
    end
    for (u0, u1) in pairs_u
        length(sys0.b[u0]) == length(sys1.b[u1]) ||
            return (; nested = false, reason = :mismatched_category_arity, df = 0)
    end

    b0 = reduce(vcat, (sys0.b[u0] for (u0, _) in pairs_u))
    b1 = reduce(vcat, (sys1.b[u1] for (_, u1) in pairs_u))
    c0 = reduce(vcat, (sys0.c[u0] for (u0, _) in pairs_u))
    c1 = reduce(vcat, (sys1.c[u1] for (_, u1) in pairs_u))
    A0 = reduce(vcat, (sys0.A[u0] for (u0, _) in pairs_u))
    A1 = reduce(vcat, (sys1.A[u1] for (_, u1) in pairs_u))

    if hp0 && hp1
        pop0 = f_simple.record.summary.population
        pop1 = f_complex.record.summary.population
        d_p0, d_p1 = pop0.design, pop1.design
        (d_p0.people == d_p1.people && d_p0.groups == d_p1.groups && d_p0.group_index == d_p1.group_index) ||
            return (; nested = false, reason = :mismatched_population_roster_or_groups, df = 0)
        eq0 = Bool(get(pop0, :equal_sd, false))
        eq1 = Bool(get(pop1, :equal_sd, false))
        (!eq0 && eq1) && return (; nested = false, reason = :free_group_sd_not_nested_in_equal_sd, df = 0)
        norm(b1 .- b0, Inf) <= 1e-9 * max(1.0, norm(b1, Inf)) ||
            return (; nested = false, reason = :non_identical_grouped_ability_slopes, df = 0)
        X0, X1 = d_p0.X, d_p1.X
        sv_x1 = size(X1, 2) > 0 ? svd(X1) : nothing
        tol_x1 = (sv_x1 === nothing || isempty(sv_x1.S)) ? 0.0 : 1e-10 * max(size(X1)...) * max(1.0, sv_x1.S[1])
        r_x1 = sv_x1 === nothing ? 0 : count(>(tol_x1), sv_x1.S)
        Ux1 = r_x1 > 0 ? view(sv_x1.U, :, 1:r_x1) : zeros(Float64, size(X1, 1), 0)
        if size(X0, 2) > 0
            maximum(abs, X0 .- Ux1 * (Ux1' * X0)) <= 1e-9 * max(1.0, maximum(abs, X0)) ||
                return (; nested = false, reason = :non_nested_population_covariates, df = 0)
        end
        sv1_g = size(A1, 2) > 0 ? svd(A1) : nothing
        tol1_g = (sv1_g === nothing || isempty(sv1_g.S)) ? 0.0 : 1e-10 * max(size(A1)...) * max(1.0, sv1_g.S[1])
        r_A1 = sv1_g === nothing ? 0 : count(>(tol1_g), sv1_g.S)
        U1_g = r_A1 > 0 ? view(sv1_g.U, :, 1:r_A1) : zeros(Float64, length(c1), 0)
        sv0_g = size(A0, 2) > 0 ? svd(A0) : nothing
        tol0_g = (sv0_g === nothing || isempty(sv0_g.S)) ? 0.0 : 1e-10 * max(size(A0)...) * max(1.0, sv0_g.S[1])
        r_A0 = sv0_g === nothing ? 0 : count(>(tol0_g), sv0_g.S)

        n_sd0 = eq0 ? 1 : length(d_p0.groups)
        n_sd1 = eq1 ? 1 : length(d_p1.groups)
        eff0_g = r_A0 + size(X0, 2) + n_sd0
        eff1_g = r_A1 + size(X1, 2) + n_sd1
        (eff0_g == d0 && eff1_g == d1 && d1 > d0) ||
            return (; nested = false, reason = :effective_rank_mismatch, df = 0)
        dd_g = c0 .- c1
        norm(dd_g .- U1_g * (U1_g' * dd_g), Inf) <= 1e-9 * max(1.0, norm(dd_g, Inf)) ||
            return (; nested = false, reason = :incompatible_affine_offsets, df = 0)
        if size(A0, 2) > 0
            maximum(abs, A0 .- U1_g * (U1_g' * A0)) <= 1e-9 * max(1.0, maximum(abs, A0)) ||
                return (; nested = false, reason = :non_nested_intercept_subspace, df = 0)
        end
        return (; nested = true, reason = :verified_interior_linear_subspace, df = d1 - d0)
    end

    nb0 = norm(b0, Inf)
    nb1 = norm(b1, Inf)
    if nb0 <= 1e-13 && nb1 <= 1e-13
        (sys0.est_sd || sys1.est_sd) && return (; nested = false, reason = :unidentified_population_sd, df = 0)
    elseif nb0 <= 1e-13 || nb1 <= 1e-13
        return (; nested = false, reason = :boundary_or_mismatched_ability_slope, df = 0)
    else
        idx_max = argmax(abs.(b0))
        alpha = b1[idx_max] / b0[idx_max]
        abs(alpha) > 1e-12 || return (; nested = false, reason = :boundary_or_mismatched_ability_slope, df = 0)
        norm(b1 .- alpha .* b0, Inf) <= 1e-9 * max(1.0, nb1) ||
            return (; nested = false, reason = :non_collinear_ability_slopes, df = 0)
        if sys0.est_sd && !sys1.est_sd
            return (; nested = false, reason = :free_sd_not_nested_in_fixed_sd, df = 0)
        elseif !sys0.est_sd && !sys1.est_sd
            abs(abs(alpha) * sys1.sd_fix - sys0.sd_fix) <= 1e-9 * max(1.0, sys0.sd_fix) ||
                return (; nested = false, reason = :incompatible_fixed_population_sd, df = 0)
        end
    end

    G0 = sys0.est_mu ? hcat(A0, reshape(b0, :, 1)) : A0
    G1 = sys1.est_mu ? hcat(A1, reshape(b1, :, 1)) : A1
    d_vec0 = sys0.est_mu ? c0 : (c0 .+ sys0.mu_fix .* b0)
    d_vec1 = sys1.est_mu ? c1 : (c1 .+ sys1.mu_fix .* b1)

    sv1 = size(G1, 2) > 0 ? svd(G1) : nothing
    tol1 = (sv1 === nothing || isempty(sv1.S)) ? 0.0 : 1e-10 * max(size(G1)...) * max(1.0, sv1.S[1])
    r_G1 = sv1 === nothing ? 0 : count(>(tol1), sv1.S)
    U1 = r_G1 > 0 ? view(sv1.U, :, 1:r_G1) : zeros(Float64, length(d_vec1), 0)

    sv0 = size(G0, 2) > 0 ? svd(G0) : nothing
    tol0 = (sv0 === nothing || isempty(sv0.S)) ? 0.0 : 1e-10 * max(size(G0)...) * max(1.0, sv0.S[1])
    r_G0 = sv0 === nothing ? 0 : count(>(tol0), sv0.S)

    eff0 = r_G0 + (sys0.est_sd ? 1 : 0)
    eff1 = r_G1 + (sys1.est_sd ? 1 : 0)
    (eff0 == d0 && eff1 == d1 && d1 > d0) ||
        return (; nested = false, reason = :effective_rank_mismatch, df = 0)

    dd = d_vec0 .- d_vec1
    res_d = norm(dd .- U1 * (U1' * dd), Inf)
    res_d <= 1e-9 * max(1.0, norm(dd, Inf)) ||
        return (; nested = false, reason = :incompatible_affine_offsets, df = 0)

    if size(G0, 2) > 0
        res_G = maximum(abs, G0 .- U1 * (U1' * G0))
        res_G <= 1e-9 * max(1.0, maximum(abs, G0)) ||
            return (; nested = false, reason = :non_nested_intercept_subspace, df = 0)
    end
    return (; nested = true, reason = :verified_interior_linear_subspace, df = d1 - d0)
end
function compare_mmle_models(pairs_vec::AbstractVector{<:Pair}; criterion::Symbol = :aic)
    criterion in (:aic, :bic, :bic_persons, :bic_observations) ||
        throw(ArgumentError("frequentist MMLE model comparison requires criterion in (:aic, :bic, :bic_persons, :bic_observations); got $(repr(criterion))"))
    length(pairs_vec) >= 2 || throw(ArgumentError("supply at least two labeled MMLE fits to compare_models"))
    labels = [strip(string(first(p))) for p in pairs_vec]
    all(!isempty, labels) && allunique(labels) || throw(ArgumentError("distinct nonempty model labels are required"))
    fits = Fit[]
    for p in pairs_vec
        v = last(p)
        v isa Fit || throw(ArgumentError("all compared models must be FrequentistMFRM.Fit objects"))
        checked(v)
        v.record.summary.method === :mmle ||
            throw(ArgumentError("model $(repr(first(p))) was estimated with JMLE; AIC/BIC model comparison requires method = :mmle"))
        push!(fits, v)
    end
    obs0 = fits[1].record.summary.observation_binding
    q_rule0 = (fits[1].record.summary.quadrature, fits[1].record.summary.quad_points, fits[1].record.summary.theta_lim)
    for (lbl, fk) in zip(labels, fits)
        fk.record.summary.observation_binding == obs0 ||
            throw(ArgumentError("model $(repr(lbl)) does not bind the exact same rating observations and category supports"))
        (fk.record.summary.quadrature, fk.record.summary.quad_points, fk.record.summary.theta_lim) == q_rule0 ||
            throw(ArgumentError("model $(repr(lbl)) uses different quadrature settings; match quadrature and quad_points for MMLE comparison"))
    end
    crit_key = criterion === :bic ? :bic_persons : criterion
    vals = [Float64(getproperty(fk.record.summary, crit_key)) for fk in fits]
    order = sortperm(vals)
    best_val = vals[order[1]]
    best_ll = fits[order[1]].record.summary.loglikelihood
    rows = [
        begin
            s = fits[idx].record.summary
            v = vals[idx]
            (;
                rank = rnk,
                model_label = labels[idx],
                model = s.model,
                n_parameters = s.n_free_parameters,
                loglikelihood = s.loglikelihood,
                deviance = s.deviance,
                aic = s.aic,
                bic_persons = s.bic_persons,
                bic_observations = s.bic_observations,
                selected_criterion = v,
                delta_criterion = v - best_val,
                delta_loglikelihood = s.loglikelihood - best_ll,
                stationarity_qualified = s.stationarity_qualified,
            )
        end for (rnk, idx) in enumerate(order)
    ]
    # Exact algebraic linear-subspace check before emitting any nested chi-square LRT
    nest_info, lrt = if length(fits) == 2
        if fits[1].record.summary.n_free_parameters == fits[2].record.summary.n_free_parameters
            ((; nested = false, reason = :equal_parameter_dimension), nothing)
        else
            i_complex = fits[1].record.summary.n_free_parameters > fits[2].record.summary.n_free_parameters ? 1 : 2
            i_simple = 3 - i_complex
            ni = _verify_mmle_nested(fits[i_simple], fits[i_complex])
            if ni.nested
                df_diff = ni.df
                raw_stat = 2.0 * (fits[i_complex].record.summary.loglikelihood - fits[i_simple].record.summary.loglikelihood)
                stat = (-1e-9 <= raw_stat < 0.0) ? 0.0 : raw_stat
                pval = stat >= 0.0 ? ccdf(Chisq(df_diff), stat) : missing
                (ni, (;
                    nested = true,
                    complex_model = labels[i_complex],
                    reduced_model = labels[i_simple],
                    lr_statistic = stat,
                    df = df_diff,
                    asymptotic_chisq_pvalue = pval,
                    note = "Verified interior linear-subspace nesting; asymptotic chi-square p-value assumes adequate sample size.",
                ))
            else
                (ni, nothing)
            end
        end
    else
        ((; nested = missing, reason = :multiple_models), nothing)
    end
    body = (;
        schema = COMPARISON_SCHEMA,
        inference_paradigm = :frequentist,
        criterion = crit_key,
        observation_binding = obs0,
        quadrature = q_rule0[1],
        quad_points = q_rule0[2],
        rows,
        nested = nest_info.nested,
        nesting_status = nest_info.reason,
        likelihood_ratio = lrt,
        warning = "Asymptotic marginal information criteria on the observed design; not cross-validated out-of-sample or Bayesian PSIS-LOO.",
    )
    return merge(body, (; report_hash = B._cache_hash(body)))
end

function contrast(f::Fit;
        facet::Union{Nothing,Symbol} = nothing,
        left = nothing,
        right = nothing,
        interaction = nothing,
        focal = nothing,
        level_1 = nothing,
        group = nothing,
        reference = nothing,
        estimand::Symbol = :vs_rest_of_panel,
        se_type::Symbol = :observed,
        interval::Union{Nothing,Real} = nothing,
        level::Union{Nothing,Real} = nothing)
    r = checked(f)
    (interval !== nothing && level !== nothing) &&
        throw(ArgumentError("supply either `interval` or `level` to contrast, not both"))
    iv = Float64(something(interval, level, 0.95))
    0.0 < iv < 1.0 || throw(ArgumentError("interval must lie in (0, 1)"))
    se_type in (:observed, :sandwich) ||
        throw(ArgumentError("se_type must be `:observed` or `:sandwich`; got $(repr(se_type))"))
    z_crit = quantile(Normal(), 0.5 * (1.0 + iv))
    prob = r.problem
    lay = r.layout

    if interaction !== nothing
        hasproperty(r, :mrcml_operator) ||
            throw(ArgumentError("interaction DFF contrast requires an MRCML frequentist fit"))
        (group !== nothing && reference !== nothing) ||
            throw(ArgumentError("interaction DFF contrast requires `group` and `reference`"))
        op = r.mrcml_operator
        resolved = B.AdditiveFacets._resolve_dff_linear_weights(
            op, interaction; focal, level_1, group, reference, estimand,
        )
        cov_rec = r.covariance
        off = cov_rec === nothing ? 0 : cov_rec.offset
        V_obs = cov_rec === nothing ? nothing : cov_rec.matrix
        V_snd = (cov_rec !== nothing && hasproperty(cov_rec, :sandwich_matrix)) ? cov_rec.sandwich_matrix : nothing
        xi_hat = r.full_parameters[(off + 1):(off + length(op.model_names))]

        rows = map(resolved.entries) do ent
            w = ent.weights
            est = dot(w, xi_hat)
            v_o = V_obs === nothing ? NaN : dot(w, V_obs * w)
            se_obs = (isfinite(v_o) && v_o >= -1e-12) ? sqrt(max(v_o, 0.0)) : missing
            v_s = V_snd === nothing ? NaN : dot(w, V_snd * w)
            se_snd = (isfinite(v_s) && v_s >= -1e-12) ? sqrt(max(v_s, 0.0)) : missing
            se_sel = se_type === :sandwich ? se_snd : se_obs
            z_st = !(se_sel === missing) && se_sel > 0 ? est / se_sel : missing
            pval = !(z_st === missing) ? 2.0 * ccdf(Normal(), abs(z_st)) : missing
            lo = !(se_sel === missing) ? est - z_crit * se_sel : missing
            hi = !(se_sel === missing) ? est + z_crit * se_sel : missing
            (;
                inference_paradigm = :frequentist,
                facet = resolved.facet,
                target_level = ent.target_level,
                group = resolved.group,
                reference = resolved.reference,
                estimand = resolved.estimand,
                parameterization = ent.mode,
                scale_factor = ent.scale_factor,
                estimate = est,
                se = se_sel,
                observed_se = se_obs,
                sandwich_se = se_snd,
                z_statistic = z_st,
                p_value = pval,
                lower = lo,
                upper = hi,
                interval = iv,
                uncertainty_basis = se_type === :sandwich ? :person_cluster_huber_white_sandwich : :constrained_observed_information_delta,
            )
        end
        return resolved.single ? only(rows) : (;
            inference_paradigm = :frequentist,
            interaction = (resolved.facet, resolved.group_role),
            group = resolved.group,
            reference = resolved.reference,
            estimand = resolved.estimand,
            interval = iv,
            rows,
        )
    end

    if group !== nothing || reference !== nothing
        (group !== nothing && reference !== nothing) ||
            throw(ArgumentError("grouped population contrast requires both `group` and `reference`"))
        hasproperty(r.summary, :population) ||
            throw(ArgumentError("grouped population contrast requires a grouped MRCML MMLE fit"))
        pop = r.summary.population
        d_pop = pop.design
        ga_i = findfirst(x -> isequal(x, group), d_pop.groups)
        gb_i = findfirst(x -> isequal(x, reference), d_pop.groups)
        (ga_i !== nothing && gb_i !== nothing && ga_i != gb_i) ||
            throw(ArgumentError("select two distinct modeled population groups"))
        others = findall(!=(d_pop.reference), d_pop.groups)
        d_xi = size(r.mrcml_operator.A_free, 2)
        int_off = Bool(get(d_pop, :has_intercept, false)) ? 1 : 0
        w_free = zeros(Float64, lay.n_free)
        if ga_i != findfirst(==(d_pop.reference), d_pop.groups)
            w_free[d_xi + int_off + only(findall(==(ga_i), others))] += 1.0
        end
        if gb_i != findfirst(==(d_pop.reference), d_pop.groups)
            w_free[d_xi + int_off + only(findall(==(gb_i), others))] -= 1.0
        end
        est = dot(w_free, r.u_free)
        V_f_obs = r.covariance.free_covariance
        V_f_snd = hasproperty(r.covariance, :sandwich_free_covariance) ? r.covariance.sandwich_free_covariance : nothing
        vo = dot(w_free, V_f_obs * w_free)
        se_obs = (isfinite(vo) && vo >= -1e-12) ? sqrt(max(vo, 0.0)) : missing
        vs = V_f_snd === nothing ? NaN : dot(w_free, V_f_snd * w_free)
        se_snd = (isfinite(vs) && vs >= -1e-12) ? sqrt(max(vs, 0.0)) : missing
        se_sel = se_type === :sandwich ? se_snd : se_obs
        z_st = !(se_sel === missing) && se_sel > 0 ? est / se_sel : missing
        pval = !(z_st === missing) ? 2.0 * ccdf(Normal(), abs(z_st)) : missing
        return (;
            inference_paradigm = :frequentist,
            group = d_pop.groups[ga_i],
            reference = d_pop.groups[gb_i],
            estimate = est,
            se = se_sel,
            observed_se = se_obs,
            sandwich_se = se_snd,
            z_statistic = z_st,
            p_value = pval,
            lower = !(se_sel === missing) ? est - z_crit * se_sel : missing,
            upper = !(se_sel === missing) ? est + z_crit * se_sel : missing,
            interval = iv,
            uncertainty_basis = se_type === :sandwich ? :person_cluster_huber_white_sandwich : :constrained_observed_information_delta,
        )
    end

    (left !== nothing && right !== nothing) ||
        throw(ArgumentError("supply `left` and `right` (or `interaction = ...` / `group = ..., reference = ...`) to contrast"))

    if hasproperty(r, :mrcml_operator)
        l_target = facet === nothing ? String(left) : "$(facet)[$(repr(left))]"
        r_target = facet === nothing ? String(right) : "$(facet)[$(repr(right))]"
        l_target != r_target || throw(ArgumentError("left and right targets must be distinct"))
        il = findfirst(==(l_target), lay.full_names)
        ir = findfirst(==(r_target), lay.full_names)
        # Fallback for unquoted FrequentistMFRM style `facet[level]`
        il === nothing && facet !== nothing && (il = findfirst(==("$(facet)[$(left)]"), lay.full_names))
        ir === nothing && facet !== nothing && (ir = findfirst(==("$(facet)[$(right)]"), lay.full_names))
        il !== nothing && ir !== nothing ||
            throw(ArgumentError("unknown MRCML model parameter(s) $(repr(l_target)), $(repr(r_target)); inspect parameter_names(fit; scale = :model)"))
        diff_est = r.full_parameters[il] - r.full_parameters[ir]
        se_obs_d = missing
        se_snd_d = missing
        cov_rec = r.covariance
        if cov_rec !== nothing
            off = cov_rec.offset
            mat = cov_rec.matrix
            ml = il - off
            mr = ir - off
            if 1 <= ml <= size(mat, 1) && 1 <= mr <= size(mat, 1)
                v = mat[ml, ml] + mat[mr, mr] - 2.0 * mat[ml, mr]
                isfinite(v) && v >= -1e-12 && (se_obs_d = sqrt(max(v, 0.0)))
                if hasproperty(cov_rec, :sandwich_matrix)
                    sm = cov_rec.sandwich_matrix
                    vs = sm[ml, ml] + sm[mr, mr] - 2.0 * sm[ml, mr]
                    isfinite(vs) && vs >= -1e-12 && (se_snd_d = sqrt(max(vs, 0.0)))
                end
            end
        end
        se_diff = se_type === :sandwich ? se_snd_d : se_obs_d
        z_stat = !(se_diff === missing) && se_diff > 0 ? diff_est / se_diff : missing
        lo = !(se_diff === missing) ? diff_est - z_crit * se_diff : missing
        hi = !(se_diff === missing) ? diff_est + z_crit * se_diff : missing
        return (;
            inference_paradigm = :frequentist,
            facet = facet === nothing ? :mrcml : facet,
            left = lay.full_names[il],
            right = lay.full_names[ir],
            estimate = diff_est,
            se = se_diff,
            observed_se = se_obs_d,
            sandwich_se = se_snd_d,
            z_statistic = z_stat,
            lower = lo,
            upper = hi,
            interval = iv,
            uncertainty_basis = se_type === :sandwich ? :person_cluster_huber_white_sandwich : :constrained_observed_information_delta,
        )
    end
    facet !== nothing || throw(ArgumentError("contrast requires `facet = :...`"))
    fi = findfirst(x -> x.name === facet, prob.facets)
    fi === nothing && throw(ArgumentError("contrast requires a declared non-person facet in $([x.name for x in prob.facets]); got $(repr(facet))"))
    fdef = prob.facets[fi]
    il = findfirst(l -> isequal(l, left) || string(l) == string(left), fdef.levels)
    ir = findfirst(l -> isequal(l, right) || string(l) == string(right), fdef.levels)
    il !== nothing && ir !== nothing || throw(ArgumentError("unknown level(s) $(repr(left)), $(repr(right)) in facet $facet"))
    il != ir || throw(ArgumentError("left and right levels must be distinct"))

    idx_l = lay.facet_full_ranges[fi][il]
    idx_r = lay.facet_full_ranges[fi][ir]
    diff_est = r.full_parameters[idx_l] - r.full_parameters[idx_r]

    se_diff = missing
    cov_rec = r.covariance
    if cov_rec !== nothing
        off = cov_rec.offset
        mat = cov_rec.matrix
        ml = idx_l - off
        mr = idx_r - off
        if 1 <= ml <= size(mat, 1) && 1 <= mr <= size(mat, 1)
            v = mat[ml, ml] + mat[mr, mr] - 2.0 * mat[ml, mr]
            v >= -1e-12 && (se_diff = sqrt(max(v, 0.0)))
        end
    end
    z_stat = !(se_diff === missing) && se_diff > 0 ? diff_est / se_diff : missing
    lo = !(se_diff === missing) ? diff_est - z_crit * se_diff : missing
    hi = !(se_diff === missing) ? diff_est + z_crit * se_diff : missing
    return (;
        inference_paradigm = :frequentist,
        facet,
        left = fdef.levels[il],
        right = fdef.levels[ir],
        estimate = diff_est,
        se = se_diff,
        z_statistic = z_stat,
        lower = lo,
        upper = hi,
        interval = iv,
        uncertainty_basis = :constrained_observed_information_delta,
    )
end

function predict_rows(f::Fit; rows = nothing, mode::Symbol = :plugin)
    r = checked(f)
    prob = r.problem
    lay = r.layout
    full = r.full_parameters
    mode in (:plugin, :marginal_new_person) ||
        throw(ArgumentError("mode must be :plugin or :marginal_new_person"))
    mode === :marginal_new_person && prob.method !== :mmle &&
        throw(ArgumentError("mode = :marginal_new_person requires an MMLE fit"))
    sel = rows === nothing ? collect(1:prob.n_obs) : collect(Int, rows)
    all(i -> 1 <= i <= prob.n_obs, sel) || throw(ArgumentError("row indices out of range 1:$(prob.n_obs)"))

    if hasproperty(r, :mrcml_operator)
        op = r.mrcml_operator
        v_pat = copy(op.c_pat)
        mul!(v_pat, op.A_free, r.eta_free, 1.0, 1.0)
        quad_m = mode === :marginal_new_person ?
            build_quadrature(r.summary.quadrature, r.summary.quad_points; sd=1.0, theta_lim=Float64(r.summary.theta_lim)) : nothing
        out_m = NamedTuple[]
        for idx in sel
            g_idx = prob.step_group[idx]
            cats = hasproperty(r, :mrcml_category_labels) ?
                r.mrcml_category_labels[g_idx] :
                collect(prob.supports[g_idx])
            prng = op.pattern_ranges[op.pattern_of_row[idx]]
            M_g = length(cats)
            probs = zeros(Float64, M_g)
            if mode === :plugin
                pr = r.person_scores[prob.person_idx[idx]]
                th = prob.method === :mmle ? Float64(pr.eap) : Float64(pr.limit_estimate)
                if !isfinite(th)
                    if isnan(th)
                        fill!(probs, NaN)
                    else
                        bvec = [op.B_pat[prng[lk]] for lk in 1:M_g]
                        b_ext = th < 0 ? minimum(bvec) : maximum(bvec)
                        ext_lks = [lk for lk in 1:M_g if abs(bvec[lk] - b_ext) <= 1e-14]
                        v_ext = [v_pat[prng[lk]] for lk in ext_lks]
                        vmax = maximum(v_ext)
                        w_ext = exp.(v_ext .- vmax)
                        w_ext ./= sum(w_ext)
                        for (j_e, lk) in enumerate(ext_lks)
                            probs[lk] = w_ext[j_e]
                        end
                    end
                else
                    lvec = [op.B_pat[prng[lk]] * th + v_pat[prng[lk]] for lk in 1:M_g]
                    mmax = maximum(lvec)
                    probs .= exp.(lvec .- mmax)
                    probs ./= sum(probs)
                end
            else
                mu_m,sd_m = _mrcml_person_law(r.summary,prob.person_idx[idx])
                for (nq, wq) in zip(quad_m.std_nodes, quad_m.weights)
                    wq == 0.0 && continue
                    th = mu_m + sd_m*nq
                    lvec = [op.B_pat[prng[lk]] * th + v_pat[prng[lk]] for lk in 1:M_g]
                    mmax = maximum(lvec)
                    pv = exp.(lvec .- mmax)
                    pv ./= sum(pv)
                    probs .+= wq .* pv
                end
            end
            exp_s = sum(cats[lk] * probs[lk] for lk in 1:M_g)
            push!(out_m, (; row = idx, person = prob.person_levels[prob.person_idx[idx]],
                observed_score = prob.raw_score[idx], categories = copy(cats),
                probabilities = probs, expected_score = exp_s, mode))
        end
        return (; inference_paradigm = :frequentist, method = prob.method, mode, rows = out_m,
            warning = "Plug-in / quadrature point probabilities do not propagate parameter estimation uncertainty.")
    end

    K_max = maximum(length, prob.supports)
    pbuf = zeros(Float64, K_max)
    quad = mode === :marginal_new_person ?
        build_quadrature(r.summary.quadrature, r.summary.quad_points; sd = r.summary.population_sd, theta_lim = Float64(r.summary.theta_lim)) : nothing
    mu_hat = mode === :marginal_new_person ? Float64(r.summary.population_mean) : 0.0

    out = NamedTuple[]
    for idx in sel
        g = prob.step_group[idx]
        sup = prob.supports[g]
        K_g = length(sup)
        srng = lay.step_full_ranges[g]
        base = 0.0
        for (fi, fdef) in enumerate(prob.facets)
            base += fdef.sign * full[lay.facet_full_ranges[fi][fdef.index[idx]]]
        end
        probs = zeros(Float64, K_g)
        if mode === :plugin
            p = prob.person_idx[idx]
            pr = r.person_scores[p]
            th = prob.method === :mmle ? Float64(pr.eap) : Float64(pr.limit_estimate)
            if !isfinite(th)
                probs[th < 0 ? 1 : K_g] = 1.0
            else
                pv = view(pbuf, 1:K_g)
                _row_probs!(pv, th + base, view(full, srng))
                probs .= pv
            end
        else
            pv = view(pbuf, 1:K_g)
            for (nq, wq) in zip(quad.nodes, quad.weights)
                wq == 0.0 && continue
                _row_probs!(pv, mu_hat + nq + base, view(full, srng))
                probs .+= wq .* pv
            end
        end
        exp_score = sum(sup[k] * probs[k] for k in 1:K_g)
        push!(out, (;
            row = idx,
            person = prob.person_levels[prob.person_idx[idx]],
            observed_score = prob.raw_score[idx],
            categories = collect(sup),
            probabilities = probs,
            expected_score = exp_score,
            mode,
        ))
    end
    return (;
        inference_paradigm = :frequentist,
        method = prob.method,
        mode,
        rows = out,
        warning = "Plug-in / quadrature point probabilities do not propagate parameter estimation uncertainty.",
    )
end

function save_result(path::AbstractString, f::Fit)
    checked(f)
    ispath(path) && throw(ArgumentError("refusing to overwrite existing file: $path"))
    mkpath(dirname(abspath(path)))
    tmp = path * ".tmp." * string(rand(UInt64), base = 16)
    open(io -> Serialization.serialize(io, f), tmp, "w")
    mv(tmp, path; force = false)
    return abspath(path)
end

function load_result(f::Fit)
    checked(f)
    return f
end

function save_computed(path::AbstractString, rep::NamedTuple)
    ispath(path) && throw(ArgumentError("refusing to overwrite existing report: $path"))
    if hasproperty(rep,:summary) && hasproperty(rep.summary,:population)
        pop = rep.summary.population
        pop = merge(pop,(;design=B.AdditiveFacets._report_population(pop.design)))
        rep = merge(rep,(;summary=merge(rep.summary,(;population=pop))))
    end
    if hasproperty(rep,:summary) && hasproperty(rep.summary,:calibration)
        cal = B.AdditiveFacets._report_calibration(rep.summary.calibration)
        rep = merge(rep,(;summary=merge(rep.summary,(;calibration=cal))))
    elseif hasproperty(rep,:summary) && hasproperty(get(rep.summary,:fixed_calibration,(;)),:groups)
        cal = B.AdditiveFacets._report_calibration_groups(rep.summary.fixed_calibration)
        rep = merge(rep,(;summary=merge(rep.summary,(;fixed_calibration=cal))))
    end
    B._SA_MOD._save_atomic_json(path, rep)
end

function check_loaded_report(parsed)
    hasproperty(parsed, :schema) && parsed.schema in (REPORT_SCHEMA, COMPARISON_SCHEMA) ||
        throw(ArgumentError("unknown FrequentistMFRM report schema"))
    return parsed
end

include("mrcml_frequentist.jl")

end # module FrequentistMFRM
