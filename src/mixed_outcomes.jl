# Stage 4 mixed-family joint outcomes: user-named outcomes (ordinal, ZOIB, binomial, beta-binomial),
# matrix-driven owner dimensions/loadings, CPC Cholesky-LKJ owner covariances, and partial-outcome masks.
const MIXED_SCHEMA = "bayesianmgmfrm.mixed_outcome_design.v1"

struct MixedLoadingEntry
    kind::Symbol       # :fixed, :normal, :lognormal
    value::Float64     # fixed value (when :fixed)
    mean::Float64      # Normal mean or LogNormal logmean
    sd::Float64        # Normal sd or LogNormal logsd
    raw::Int           # 0 when :fixed
end

struct MixedOwnerBlock
    name::Symbol
    sign::Float64
    levels::Vector{Any}
    index::Vector{Int}
    dim_names::Vector{Symbol}
    D_dim::Int
    raws::Vector{UnitRange{Int}}      # length D_dim, each length L_o
    hyps::Vector{Int}                 # length D_dim, 0 if fixed SD
    sds_fixed::Vector{Float64}
    logmeans::Vector{Float64}
    logsds::Vector{Float64}
    corr_kind::Symbol                 # :none, :fixed, :lkj
    corr_eta::Float64
    corr_raw::UnitRange{Int}
    alphas::Vector{Float64}
    logbetas::Vector{Float64}
    loadings::Matrix{MixedLoadingEntry} # M x D_dim
    declaration_kind::Symbol          # :shared_scalar, :loaded_1d, :multidimensional
end

struct MixedOutcomeTerm
    outcome_idx::Int
    outcome::Symbol
    owner::Symbol                     # :response, :person, or facet symbol
    column::Union{Nothing,Symbol}     # nothing => outcome intercept
    mean::Float64
    sd::Float64
    raw::Int
    values::Vector{Float64}           # length E (event-expanded values with owner sign)
    owner_values::Vector{Float64}     # length L_o when owner != :response, else empty
end

struct MixedOutcomeChannel
    name::Symbol
    family::Symbol                    # :ordinal, :zero_one_inflated_beta, :binomial, :beta_binomial
    score_col::Symbol
    direction::Symbol                 # :higher_is_more or :higher_is_less
    dir_sign::Float64                 # +1.0 or -1.0
    version::Union{Nothing,String}
    observed::BitVector               # length E
    obs_rows::Vector{Int}
    # Ordinal fields
    categories::Vector{Int}
    y_ord::Vector{Int}                # 1..K on observed rows, 0 on missing
    step_sd::Float64
    step_scale::Float64
    step_raw::UnitRange{Int}
    # Bounded ZOIB fields
    bounds::Tuple{Float64,Float64}
    width::Float64
    log_width::Float64
    y_zoib::Vector{Float64}           # [0, 1] on observed rows, NaN on missing
    prec_logmean::Float64
    prec_logsd::Float64
    prec_raw::Int
    ep_mean::Float64
    ep_sd::Float64
    ep_raw::Int
    up_mean::Float64
    up_sd::Float64
    up_raw::Int
    # Count fields
    trials_col::Union{Nothing,Symbol}
    y_count::Vector{Int}
    trials::Vector{Int}
    logchoose::Vector{Float64}
end

struct MixedOutcomeTarget <: AbstractTarget
    table::Dict{Symbol,Vector}
    columns::NamedTuple
    person::Vector{Int}
    people::Vector{Any}
    facets::Vector{Block}
    owners::Vector{MixedOwnerBlock}
    outcomes::Vector{MixedOutcomeChannel}
    terms::Vector{MixedOutcomeTerm}
    specification::NamedTuple
    groups::NamedTuple
    dimension::Int
    allocation::NamedTuple
end

_mixed_absent(x) = x === nothing || ismissing(x)

function _parse_loading_entry(x, label::AbstractString, offset::Ref{Int})
    if x isa Real && !(x isa Bool)
        v = Float64(x)
        isfinite(v) || throw(ArgumentError("$label fixed loading must be finite"))
        return MixedLoadingEntry(:fixed, v, 0.0, 0.0, 0)
    elseif x isa D.LogNormal
        lm, ls = Float64.(D.params(x))
        isfinite(lm) && isfinite(ls) && ls > 0 || throw(ArgumentError("$label LogNormal loading prior invalid"))
        offset[] += 1
        return MixedLoadingEntry(:lognormal, 0.0, lm, ls, offset[])
    elseif x isa D.Normal
        m, s = Float64.(D.params(x))
        isfinite(m) && isfinite(s) && s > 0 || throw(ArgumentError("$label Normal loading prior invalid"))
        offset[] += 1
        return MixedLoadingEntry(:normal, 0.0, m, s, offset[])
    end
    throw(ArgumentError("$label loading must be a finite Real, LogNormal, or Normal prior"))
end

function _parse_loadings_matrix(raw_loadings, out_names::Vector{Symbol}, dim_names::Vector{Symbol}, owner::Symbol, offset::Ref{Int})
    M = length(out_names); D_dim = length(dim_names)
    mat = Matrix{MixedLoadingEntry}(undef, M, D_dim)
    if D_dim == 1 && raw_loadings isa NamedTuple
        _keys(raw_loadings, Tuple(out_names), Symbol("$(owner)_loadings"))
        for (c, oname) in enumerate(out_names)
            mat[c, 1] = _parse_loading_entry(getproperty(raw_loadings, oname), "$owner.loadings.$oname", offset)
        end
        return mat
    elseif D_dim == 1 && raw_loadings isa AbstractVector
        length(raw_loadings) == M || throw(ArgumentError("$owner loadings vector must have length $M"))
        for c in 1:M
            mat[c, 1] = _parse_loading_entry(raw_loadings[c], "$owner.loadings[$c]", offset)
        end
        return mat
    elseif raw_loadings isa AbstractMatrix
        size(raw_loadings) == (M, D_dim) || throw(ArgumentError("$owner loadings matrix must have size ($M, $D_dim)"))
        for d in 1:D_dim, c in 1:M
            mat[c, d] = _parse_loading_entry(raw_loadings[c, d], "$owner.loadings[$c,$d]", offset)
        end
        return mat
    elseif raw_loadings isa NamedTuple
        _keys(raw_loadings, Tuple(out_names), Symbol("$(owner)_loadings"))
        for (c, oname) in enumerate(out_names)
            row = getproperty(raw_loadings, oname)
            if row isa NamedTuple
                _keys(row, Tuple(dim_names), Symbol("$(owner)_loadings_$(oname)"))
                for (d, dname) in enumerate(dim_names)
                    mat[c, d] = _parse_loading_entry(getproperty(row, dname), "$owner.loadings.$oname.$dname", offset)
                end
            elseif row isa Union{Tuple,AbstractVector}
                length(row) == D_dim || throw(ArgumentError("$owner.loadings.$oname must have length $D_dim"))
                for d in 1:D_dim
                    mat[c, d] = _parse_loading_entry(row[d], "$owner.loadings.$oname[$d]", offset)
                end
            else
                throw(ArgumentError("unsupported row in $owner.loadings.$oname"))
            end
        end
        return mat
    end
    throw(ArgumentError("unsupported loadings declaration for $owner"))
end

function _compile_mixed_owner(owner::Symbol, spec_val, levels::Vector{Any}, index::Vector{Int},
        out_names::Vector{Symbol}, offset::Ref{Int})
    M = length(out_names); L_o = length(levels)
    sgn = owner === :person ? 1.0 : -1.0
    if !(spec_val isa NamedTuple)
        pr = _population_parameters(spec_val, owner)
        pr.kind === :lognormal && L_o < 2 && throw(ArgumentError("estimated SD for $owner needs at least two levels"))
        r = (offset[] + 1):(offset[] + L_o); offset[] += L_o
        h = 0
        if pr.kind === :lognormal
            offset[] += 1; h = offset[]
        end
        loads = fill(MixedLoadingEntry(:fixed, 1.0, 0.0, 0.0, 0), M, 1)
        return MixedOwnerBlock(owner, sgn, levels, index, [:shared], 1, [r], [h],
            [pr.kind === :fixed ? pr.sd : 1.0], [pr.kind === :lognormal ? pr.logmean : 0.0],
            [pr.kind === :lognormal ? pr.logsd : 1.0], :none, 0.0, 1:0, Float64[], Float64[], loads, :shared_scalar)
    end
    if hasproperty(spec_val, :sd)
        _keys(spec_val, (:sd, :loadings), Symbol("population_$(owner)"))
        pr = _population_parameters(spec_val.sd, owner)
        pr.kind === :lognormal && L_o < 2 && throw(ArgumentError("estimated SD for $owner needs at least two levels"))
        r = (offset[] + 1):(offset[] + L_o); offset[] += L_o
        h = 0
        if pr.kind === :lognormal
            offset[] += 1; h = offset[]
        end
        loads = _parse_loadings_matrix(spec_val.loadings, out_names, [:shared], owner, offset)
        return MixedOwnerBlock(owner, sgn, levels, index, [:shared], 1, [r], [h],
            [pr.kind === :fixed ? pr.sd : 1.0], [pr.kind === :lognormal ? pr.logmean : 0.0],
            [pr.kind === :lognormal ? pr.logsd : 1.0], :none, 0.0, 1:0, Float64[], Float64[], loads, :loaded_1d)
    end
    hasproperty(spec_val, :sds) || throw(ArgumentError("population.$owner NamedTuple must supply (sd, loadings) or ([dimensions,] sds, correlation[, loadings])"))
    allowed_keys = Set((:dimensions, :sds, :correlation, :loadings))
    issubset(Set(keys(spec_val)), allowed_keys) && hasproperty(spec_val, :correlation) ||
        throw(ArgumentError("population.$owner keys must be drawn from (:dimensions, :sds, :correlation, :loadings) with :sds and :correlation required"))
    spec_val.sds isa NamedTuple && !isempty(spec_val.sds) || throw(ArgumentError("population.$owner.sds must be a nonempty NamedTuple"))
    dim_names = collect(keys(spec_val.sds)); D_dim = length(dim_names)
    if hasproperty(spec_val, :dimensions)
        decl_dims = Symbol[Symbol(x) for x in spec_val.dimensions]
        decl_dims == dim_names || throw(ArgumentError("population.$owner.dimensions $decl_dims must match keys(sds) $dim_names in order"))
    end
    prs = [_population_parameters(getproperty(spec_val.sds, d), Symbol("$(owner)_$(d)")) for d in dim_names]
    any(p -> p.kind === :lognormal, prs) && L_o < 2 && throw(ArgumentError("estimated SD for $owner needs at least two levels"))
    raws = UnitRange{Int}[]; hyps = zeros(Int, D_dim)
    for d in 1:D_dim
        push!(raws, (offset[] + 1):(offset[] + L_o)); offset[] += L_o
    end
    for d in 1:D_dim
        if prs[d].kind === :lognormal
            offset[] += 1; hyps[d] = offset[]
        end
    end
    cp = spec_val.correlation
    corr_kind = :fixed; corr_eta = 0.0; cr = 1:0; alphas = Float64[]; logbetas = Float64[]
    if D_dim == 1
        (cp isa Real && !(cp isa Bool) && cp == 0) || throw(ArgumentError("1D population.$owner correlation must be 0"))
        corr_kind = :none
    elseif cp isa D.LKJ
        L_o >= 2 || throw(ArgumentError("LKJ correlation for $owner needs at least two owner levels"))
        ldim, eta = D.params(cp)
        ldim == D_dim && isfinite(eta) && eta > 0 || throw(ArgumentError("population.$owner correlation requires LKJ($D_dim, eta) with finite eta > 0"))
        corr_kind = :lkj; corr_eta = Float64(eta)
        nc = (D_dim * (D_dim - 1)) ÷ 2
        cr = (offset[] + 1):(offset[] + nc); offset[] += nc
        for i in 2:D_dim, j in 1:(i - 1)
            al = corr_eta + (D_dim - 1 - j) / 2
            push!(alphas, al); push!(logbetas, SF.logbeta(0.5, al))
        end
    elseif cp isa Real && !(cp isa Bool) && cp == 0
        corr_kind = :fixed
    else
        throw(ArgumentError("population.$owner correlation must be LKJ($D_dim, eta) or 0"))
    end
    loads = if hasproperty(spec_val, :loadings)
        _parse_loadings_matrix(spec_val.loadings, out_names, dim_names, owner, offset)
    else
        dim_names == out_names || throw(ArgumentError("omit population.$owner.loadings only when sds keys match outcome names $out_names"))
        [MixedLoadingEntry(:fixed, c == d ? 1.0 : 0.0, 0.0, 0.0, 0) for c in 1:M, d in 1:D_dim]
    end
    MixedOwnerBlock(owner, sgn, levels, index, dim_names, D_dim, raws, hyps,
        [p.kind === :fixed ? p.sd : 1.0 for p in prs],
        [p.kind === :lognormal ? p.logmean : 0.0 for p in prs],
        [p.kind === :lognormal ? p.logsd : 1.0 for p in prs],
        corr_kind, corr_eta, cr, alphas, logbetas, loads, :multidimensional)
end

function _compile_mixed_outcome(oname::Symbol, ospec, table, E::Int, offset::Ref{Int})
    ospec isa NamedTuple && hasproperty(ospec, :family) && hasproperty(ospec, :score) && hasproperty(ospec, :intercept) ||
        throw(ArgumentError("outcome $oname must declare family, score, and intercept"))
    fam = ospec.family
    fam in (:ordinal, :zero_one_inflated_beta, :binomial, :beta_binomial) ||
        throw(ArgumentError("outcome $oname family must be :ordinal, :zero_one_inflated_beta, :binomial, or :beta_binomial"))
    scol = ospec.score; scol isa Symbol || throw(ArgumentError("outcome $oname score must be a column symbol"))
    dir = get(ospec, :direction, :higher_is_more)
    dir in (:higher_is_more, :higher_is_less) || throw(ArgumentError("outcome $oname direction must be :higher_is_more or :higher_is_less"))
    dsgn = dir === :higher_is_more ? 1.0 : -1.0
    ver_raw = get(ospec, :version, nothing)
    ver = ver_raw === nothing ? nothing : (ver_raw isa Union{AbstractString,Symbol} && !isempty(String(ver_raw)) ? String(ver_raw) : throw(ArgumentError("outcome $oname version must be a nonempty String or Symbol")))

    raw_col = collect(B._column(table, scol))
    B._check_length!(E, raw_col, scol)
    obs = BitVector([!_mixed_absent(v) for v in raw_col])
    obs_rows = findall(obs)
    !isempty(obs_rows) || throw(ArgumentError("outcome $oname has zero observed events"))

    if fam === :ordinal
        allowed = Set((:family, :score, :categories, :step_sd, :intercept, :direction, :version, :predictors))
        issubset(Set(keys(ospec)), allowed) && hasproperty(ospec, :categories) ||
            throw(ArgumentError("ordinal outcome $oname requires categories (and step_sd when >2 categories), with no extraneous keys"))
        cats = B._normalize_category_levels(ospec.categories)
        K = length(cats); H = K - 1
        ssd = H > 1 ? (hasproperty(ospec, :step_sd) ? _sd(ospec.step_sd, true, Symbol("$(oname)_step_sd")) : throw(ArgumentError("ordinal outcome $oname with $K categories requires step_sd"))) :
              (hasproperty(ospec, :step_sd) ? _sd(ospec.step_sd, false, Symbol("$(oname)_step_sd")) : 0.0)
        sscale = H > 1 ? ssd * sqrt(H / (H - 1)) : 0.0
        cat_map = Dict(k => idx for (idx, k) in enumerate(cats))
        y_ord = zeros(Int, E)
        for e in obs_rows
            iv = B._score_to_int(raw_col[e], scol)
            haskey(cat_map, iv) || throw(ArgumentError("ordinal outcome $oname at row $e has score $iv outside declared categories $cats"))
            y_ord[e] = cat_map[iv]
        end
        sraw = H > 1 ? ((offset[] + 1):(offset[] + H - 1)) : (1:0)
        offset[] += max(0, H - 1)
        return MixedOutcomeChannel(oname, fam, scol, dir, dsgn, ver, obs, obs_rows,
            cats, y_ord, ssd, sscale, sraw,
            (0.0, 1.0), 1.0, 0.0, Float64[], 0.0, 1.0, 0, 0.0, 1.0, 0, 0.0, 1.0, 0,
            nothing, Int[], Int[], Float64[]), raw_col
    elseif fam === :zero_one_inflated_beta
        allowed = Set((:family, :score, :bounds, :precision, :endpoint_logit, :upper_logit, :intercept, :direction, :version, :predictors))
        issubset(Set(keys(ospec)), allowed) && all(k -> hasproperty(ospec, k), (:bounds, :precision, :endpoint_logit, :upper_logit)) ||
            throw(ArgumentError("ZOIB outcome $oname requires bounds, precision, endpoint_logit, and upper_logit"))
        bds = ospec.bounds
        bds isa Tuple && length(bds) == 2 && all(x -> x isa Real && !(x isa Bool) && isfinite(x), bds) ||
            throw(ArgumentError("ZOIB outcome $oname bounds must be two finite reals"))
        lo, hi = Float64.(bds); width = hi - lo
        isfinite(width) && width > 0 || throw(ArgumentError("ZOIB outcome $oname bounds must have positive width"))
        pp = _population_parameters(ospec.precision, Symbol("$(oname)_precision"))
        pp.kind === :lognormal || throw(ArgumentError("ZOIB outcome $oname precision requires a LogNormal prior"))
        zp = _normal_parameters(ospec.endpoint_logit, Symbol("$(oname)_endpoint_logit"))
        hp = _normal_parameters(ospec.upper_logit, Symbol("$(oname)_upper_logit"))
        y_zoib = fill(NaN, E)
        for e in obs_rows
            v = raw_col[e]
            v isa Real && !(v isa Bool) && isfinite(v) && lo <= v <= hi ||
                throw(ArgumentError("ZOIB outcome $oname score at row $e must be finite and within bounds ($lo, $hi)"))
            fv = Float64(v); y01 = (fv - lo) / width
            ((fv == lo) == (y01 == 0.0)) && ((fv == hi) == (y01 == 1.0)) ||
                throw(ArgumentError("ZOIB outcome $oname normalization loses endpoint identity at row $e"))
            y_zoib[e] = y01
        end
        offset[] += 1; praw = offset[]
        offset[] += 1; eraw = offset[]
        offset[] += 1; uraw = offset[]
        return MixedOutcomeChannel(oname, fam, scol, dir, dsgn, ver, obs, obs_rows,
            Int[], Int[], 0.0, 0.0, 1:0,
            (lo, hi), width, log(width), y_zoib, pp.logmean, pp.logsd, praw, zp.mean, zp.sd, eraw, hp.mean, hp.sd, uraw,
            nothing, Int[], Int[], Float64[]), raw_col
    else
        bb = fam === :beta_binomial
        allowed = Set(bb ? (:family, :score, :trials, :precision, :intercept, :direction, :version, :predictors) :
                           (:family, :score, :trials, :intercept, :direction, :version, :predictors))
        issubset(Set(keys(ospec)), allowed) && hasproperty(ospec, :trials) && (!bb || hasproperty(ospec, :precision)) ||
            throw(ArgumentError("count outcome $oname requires trials" * (bb ? " and precision" : "")))
        tcol = ospec.trials; tcol isa Symbol || throw(ArgumentError("outcome $oname trials must be a column symbol"))
        tr_raw = collect(B._column(table, tcol))
        B._check_length!(E, tr_raw, tcol)
        obs_scores = [raw_col[e] for e in obs_rows]
        obs_trials = [tr_raw[e] for e in obs_rows]
        ys = count_integers(obs_scores, Symbol("$(oname)_successes"))
        ns = count_integers(obs_trials, Symbol("$(oname)_trials"); positive = true)
        all(ys .<= ns) || throw(ArgumentError("count outcome $oname has successes exceeding declared trials"))
        y_cnt = zeros(Int, E); tr_vec = zeros(Int, E); lch = zeros(Float64, E)
        for (idx, e) in enumerate(obs_rows)
            yk = ys[idx]; nm = ns[idx]
            y_cnt[e] = yk; tr_vec[e] = nm
            lch[e] = SF.loggamma(Float64(nm) + 1.0) - SF.loggamma(Float64(yk) + 1.0) - SF.loggamma(Float64(nm - yk) + 1.0)
        end
        praw = 0; plm = 0.0; pls = 1.0
        if bb
            pp = _population_parameters(ospec.precision, Symbol("$(oname)_precision"))
            pp.kind === :lognormal || throw(ArgumentError("beta-binomial outcome $oname precision requires a LogNormal prior"))
            offset[] += 1; praw = offset[]; plm = pp.logmean; pls = pp.logsd
        end
        return MixedOutcomeChannel(oname, fam, scol, dir, dsgn, ver, obs, obs_rows,
            Int[], Int[], 0.0, 0.0, 1:0,
            (0.0, 1.0), 1.0, 0.0, Float64[], plm, pls, praw, 0.0, 1.0, 0, 0.0, 1.0, 0,
            tcol, y_cnt, tr_vec, lch), raw_col
    end
end

function _mixed_loading_ref_value(e::MixedLoadingEntry)
    e.kind === :fixed ? e.value : e.kind === :lognormal ? exp(e.mean) : (e.mean == 0.0 ? 1.0 : e.mean)
end

function mixed_allocation(owners::Vector{MixedOwnerBlock}, channels::Vector{MixedOutcomeChannel},
        terms::Vector{MixedOutcomeTerm}, person::Vector{Int}, people::Vector{Any}, facets::Vector{Block}, E::Int)
    M = length(channels); reasons = String[]; warnings = String[]
    # 1. Missing owner levels across ALL observed events
    missing_levels = String[]
    for ob in owners
        seen = Set{Int}()
        for e in 1:E
            any(ch -> ch.observed[e], channels) && push!(seen, ob.index[e])
        end
        for (j, id) in enumerate(ob.levels)
            j in seen || push!(missing_levels, "$(ob.name)[$(repr(id))]")
        end
    end
    isempty(missing_levels) || push!(reasons, "Unobserved owner levels: $(join(missing_levels, ", ")).")

    # 2. Per-outcome fixed predictor + intercept rank check with tall-matrix tolerance (C7)
    outcome_ranks = NamedTuple[]
    for (c, ch) in enumerate(channels)
        cterms = [t for t in terms if t.outcome_idx == c]
        Xo = hcat([t.values[ch.obs_rows] for t in cterms]...)
        Xn = mapslices(v -> (s = norm(v); s == 0 ? v : v ./ s), Xo; dims = 1)
        rtol = max(size(Xn)...) * eps(Float64)
        rk = rank(Xn; rtol)
        rk == length(cterms) || push!(reasons, "Outcome $(ch.name) fixed predictors have rank $rk/$(length(cterms)).")
        push!(outcome_ranks, (; outcome = ch.name, n_observed = length(ch.obs_rows), rank = rk, columns = length(cterms)))
    end

    # 3. Loading scale, sign, and rotational identification checks
    for ob in owners
        for d in 1:ob.D_dim
            col_entries = ob.loadings[:, d]
            active_c = [c for c in 1:M if !(col_entries[c].kind === :fixed && col_entries[c].value == 0.0)]
            if isempty(active_c)
                push!(reasons, "Owner $(ob.name) dimension $(ob.dim_names[d]) has all-zero loadings.")
                continue
            end
            has_fixed_nonzero = any(c -> col_entries[c].kind === :fixed && col_entries[c].value != 0.0, active_c)
            if ob.hyps[d] > 0 && !has_fixed_nonzero
                push!(reasons, "Owner $(ob.name) dimension $(ob.dim_names[d]) has both estimated SD and all-free loadings; fix either sd or a marker loading.")
            end
            has_sign_anchor = has_fixed_nonzero || any(c -> col_entries[c].kind === :lognormal, active_c)
            if !has_sign_anchor
                push!(reasons, "Owner $(ob.name) dimension $(ob.dim_names[d]) has unconstrained Normal loadings with no sign anchor; fix a marker loading or use LogNormal positive loadings.")
            end
        end
        if ob.D_dim >= 2
            Lref = [_mixed_loading_ref_value(ob.loadings[c, d]) for c in 1:M, d in 1:ob.D_dim]
            rk_L = rank(Lref; rtol = max(size(Lref)...) * eps(Float64))
            rk_L == ob.D_dim || push!(reasons, "Owner $(ob.name) loading matrix has column rank $rk_L/$(ob.D_dim).")
            has_any_free_loading = any(e -> e.kind !== :fixed, ob.loadings)
            if has_any_free_loading && ob.corr_kind === :lkj
                # Check dedicated pure marker per dimension (Anderson-Rubin / echelon condition)
                for d in 1:ob.D_dim
                    has_pure = any(1:M) do c
                        e_cd = ob.loadings[c, d]
                        !(e_cd.kind === :fixed && e_cd.value == 0.0) &&
                            all(d2 -> d2 == d || (ob.loadings[c, d2].kind === :fixed && ob.loadings[c, d2].value == 0.0), 1:ob.D_dim)
                    end
                    has_pure || push!(reasons, "Owner $(ob.name) dimension $(ob.dim_names[d]) lacks a dedicated marker outcome under correlated free loadings.")
                end
            end
        end
    end

    # 4. O(E * M^2) grouped Frobenius covariance-Gram screen across all free variance/correlation kernels (C2)
    # Kernel list: (owner_idx, M x M signed loading symmetric matrix, label)
    cov_kernels = Tuple{Int,Matrix{Float64},String}[]
    dsigns = [ch.dir_sign for ch in channels]
    for (oi, ob) in enumerate(owners)
        Lref = [dsigns[c] * _mixed_loading_ref_value(ob.loadings[c, d]) for c in 1:M, d in 1:ob.D_dim]
        for d in 1:ob.D_dim
            if length(ob.levels) > 1 && (ob.hyps[d] > 0 || ob.sds_fixed[d] > 0)
                Mat = Lref[:, d:d] * transpose(Lref[:, d:d])
                push!(cov_kernels, (oi, Mat, "var[$(ob.name),$(ob.dim_names[d])]"))
            end
        end
        if ob.corr_kind === :lkj
            for d1 in 2:ob.D_dim, d2 in 1:(d1 - 1)
                Mat = Lref[:, d1:d1] * transpose(Lref[:, d2:d2]) .+ Lref[:, d2:d2] * transpose(Lref[:, d1:d1])
                push!(cov_kernels, (oi, Mat, "cov[$(ob.name),$(ob.dim_names[d2]),$(ob.dim_names[d1])]"))
            end
        end
    end
    n_cov = length(cov_kernels)
    cov_rank = n_cov
    if n_cov > 0
        # Precompute per-owner level x outcome observation counts
        owner_counts = [zeros(Float64, length(ob.levels), M) for ob in owners]
        for e in 1:E, c in 1:M
            if channels[c].observed[e]
                for (oi, ob) in enumerate(owners)
                    owner_counts[oi][ob.index[e], c] += 1.0
                end
            end
        end
        # Precompute owner-pair (M x M) count matrices W_{oi, oj}[c1, c2] = sum_{groups} n_{g, c1} * n_{g, c2}
        W_pair = Matrix{Matrix{Float64}}(undef, length(owners), length(owners))
        for oi in eachindex(owners)
            W_pair[oi, oi] = transpose(owner_counts[oi]) * owner_counts[oi]
            for oj in (oi + 1):length(owners)
                pair_counts = Dict{Tuple{Int,Int},Vector{Float64}}()
                idx1 = owners[oi].index; idx2 = owners[oj].index
                for e in 1:E
                    key = (idx1[e], idx2[e])
                    v = get!(pair_counts, key) do
                        zeros(Float64, M)
                    end
                    for c in 1:M
                        channels[c].observed[e] && (v[c] += 1.0)
                    end
                end
                W = zeros(Float64, M, M)
                for v in values(pair_counts)
                    for c2 in 1:M, c1 in 1:M
                        W[c1, c2] += v[c1] * v[c2]
                    end
                end
                W_pair[oi, oj] = W
                W_pair[oj, oi] = W
            end
        end
        Gram = zeros(Float64, n_cov, n_cov)
        for k1 in 1:n_cov
            oi, M1, _ = cov_kernels[k1]
            for k2 in k1:n_cov
                oj, M2, _ = cov_kernels[k2]
                W = W_pair[oi, oj]
                s = 0.0
                for c2 in 1:M, c1 in 1:M
                    s += M1[c1, c2] * M2[c1, c2] * W[c1, c2]
                end
                Gram[k1, k2] = s; Gram[k2, k1] = s
            end
        end
        dscales = [Gram[k, k] > 0 ? sqrt(Gram[k, k]) : 1.0 for k in 1:n_cov]
        Gnorm = [Gram[k1, k2] / (dscales[k1] * dscales[k2]) for k1 in 1:n_cov, k2 in 1:n_cov]
        cov_rank = rank(Symmetric(Gnorm); rtol = 1e-10)
        cov_rank == n_cov || push!(reasons, "Owner variance/covariance kernels have Frobenius Gram rank $cov_rank/$n_cov (confounded owner hierarchy or zero co-observed outcome overlap).")
    end

    (; identified = isempty(reasons), reasons, missing_levels, outcome_ranks,
       covariance_rank = cov_rank, covariance_columns = n_cov,
       method = :mixed_outcome_predictor_svd_and_grouped_frobenius_gram,
       slope_warnings = warnings)
end

function mixed_outcome_model(table; outcomes::NamedTuple, person::Symbol, facets::NamedTuple,
        population::NamedTuple, predictors::NamedTuple = (;), decompose = nothing,
        levels = nothing, performance = nothing, assessment = nothing)
    reserved = (:person, :response, :steps, :global, :score, :performance, :assessment)
    !isempty(outcomes) || throw(ArgumentError("outcomes must declare at least one named outcome"))
    out_names = collect(keys(outcomes))
    all(k -> !(k in reserved), out_names) || throw(ArgumentError("outcome names cannot use reserved roles"))
    all(k -> !(k in reserved) && !(k in out_names), keys(facets)) || throw(ArgumentError("facet names must be distinct from reserved roles and outcome names"))
    all(x -> x isa Symbol, values(facets)) || throw(ArgumentError("facet mappings must name columns"))
    all(x -> x === nothing || x isa Symbol, (performance, assessment)) || throw(ArgumentError("performance/assessment must be column symbols"))
    assessment !== nothing && performance === nothing && throw(ArgumentError("assessment requires performance ownership"))

    owner_syms = [:person; collect(keys(facets))]
    _keys(population, Tuple(owner_syms), :population)
    all(k -> k in (owner_syms..., :response), keys(predictors)) || throw(ArgumentError("unknown predictor owner"))

    id_cols = Symbol[person, values(facets)...]
    performance !== nothing && !(performance in values(facets)) && push!(id_cols, performance)
    assessment !== nothing && push!(id_cols, assessment)
    score_cols = Symbol[getproperty(outcomes, oname).score for oname in out_names]
    trial_cols = Symbol[getproperty(outcomes, oname).trials for oname in out_names if hasproperty(getproperty(outcomes, oname), :trials)]
    allunique([id_cols; score_cols]) || throw(ArgumentError("identity and outcome score columns must be distinct"))
    isempty(intersect(Set(trial_cols), Set([id_cols; score_cols]))) || throw(ArgumentError("trials columns must be distinct from identity and score columns"))

    raw = Dict{Symbol,Vector}(c => collect(B._column(table, c)) for c in id_cols)
    E = length(raw[person]); E > 0 || throw(ArgumentError("events cannot be empty"))
    for (c, x) in raw
        B._check_length!(E, x, c); _labels(x, c)
    end
    if levels !== nothing
        _keys(levels, (:person, :facets), :levels); _keys(levels.facets, keys(facets), :facet_levels)
    end
    p_idx, p_lev = _labels(raw[person], :person, levels === nothing ? nothing : levels.person)
    blocks = Block[]
    for (name, c) in pairs(facets)
        ix, lev = _labels(raw[c], name, levels === nothing ? nothing : levels.facets[name])
        push!(blocks, Block(name, c, lev, ix, 0.0, 0.0, 1:0))
    end
    columns = (; person, outcomes = (;(oname => getproperty(outcomes, oname).score for oname in out_names)...), facets, performance, assessment)
    groups = _groups(raw, (; person, score = first(score_cols), facets, performance, assessment), p_idx, blocks)
    identity = (; table = raw, columns, person = p_idx, people = p_lev, facets = blocks)
    derived, dec = decompose === nothing ? (Dict{Symbol,Vector}(), nothing) : decompose_predictors(identity, table, decompose)
    merge!(raw, derived)

    offset = Ref(0)
    owner_blocks = MixedOwnerBlock[]
    for oname in owner_syms
        levs = _owner_levels(identity, oname)
        ix = _owner_index(identity, oname)
        push!(owner_blocks, _compile_mixed_owner(oname, getproperty(population, oname), levs, ix, out_names, offset))
    end

    channels = MixedOutcomeChannel[]
    for oname in out_names
        ch, rcol = _compile_mixed_outcome(oname, getproperty(outcomes, oname), table, E, offset)
        raw[ch.score_col] = rcol
        ch.trials_col !== nothing && (raw[ch.trials_col] = collect(B._column(table, ch.trials_col)))
        push!(channels, ch)
    end
    for e in 1:E
        any(ch -> ch.observed[e], channels) ||
            throw(ArgumentError("event at row $e has no observed outcomes; drop completely empty rows before fitting"))
    end

    # Compile shared-declaration predictors (expanded per outcome) + outcome-specific predictors + outcome intercepts
    terms = MixedOutcomeTerm[]
    used_cols = Set([id_cols; score_cols; trial_cols])
    top_pred_rec = Pair{Symbol,Any}[]
    for (owner, cols) in pairs(predictors)
        _named(cols, "predictors.$owner"); crecs = Pair{Symbol,Any}[]
        for (col, pr) in pairs(cols)
            col in used_cols && throw(ArgumentError("predictor $col cannot reuse an identity, score, or trials column"))
            x = haskey(derived, col) ? derived[col] : _numeric_column(table, col, E)
            raw[col] = x
            ovals = owner === :response ? Float64[] : _owned_values(identity, owner, col, x)
            osgn = owner in (:person, :response) ? 1.0 : -1.0
            evals = owner === :response ? Float64.(x) : osgn .* ovals[_owner_index(identity, owner)]
            if pr isa NamedTuple
                _keys(pr, Tuple(out_names), Symbol("$(owner)_$(col)_outcomes"))
                per_out_rec = Pair{Symbol,Any}[]
                any_active = false
                for (c, ch) in enumerate(channels)
                    p_oc = getproperty(pr, ch.name)
                    if p_oc === nothing
                        push!(per_out_rec, ch.name => nothing)
                    else
                        any_active = true
                        np = _normal_parameters(p_oc, "$(owner).$(col).$(ch.name)")
                        offset[] += 1
                        push!(terms, MixedOutcomeTerm(c, ch.name, owner, col, np.mean, np.sd, offset[], evals, ovals))
                        push!(per_out_rec, ch.name => np)
                    end
                end
                any_active || throw(ArgumentError("predictor $owner.$col cannot be nothing on every outcome"))
                push!(crecs, col => (; kind = :by_outcome, outcomes = (; per_out_rec...)))
            else
                np = _normal_parameters(pr, "$owner.$col")
                for (c, ch) in enumerate(channels)
                    offset[] += 1
                    push!(terms, MixedOutcomeTerm(c, ch.name, owner, col, np.mean, np.sd, offset[], evals, ovals))
                end
                push!(crecs, col => np)
            end
        end
        push!(top_pred_rec, owner => (; crecs...))
    end

    out_specs_rec = Pair{Symbol,Any}[]
    for (c, ch) in enumerate(channels)
        ospec = getproperty(outcomes, ch.name)
        opred_rec = Pair{Symbol,Any}[]
        if hasproperty(ospec, :predictors)
            opreds = _named(ospec.predictors, "outcomes.$(ch.name).predictors")
            for (owner, cols) in pairs(opreds)
                owner in (owner_syms..., :response) || throw(ArgumentError("unknown predictor owner $owner in outcome $(ch.name)"))
                _named(cols, "outcomes.$(ch.name).predictors.$owner"); crecs = Pair{Symbol,Any}[]
                for (col, pr) in pairs(cols)
                    col in used_cols && throw(ArgumentError("predictor $col cannot reuse an identity, score, or trials column"))
                    any(t -> t.outcome_idx == c && t.owner === owner && t.column === col, terms) &&
                        throw(ArgumentError("duplicate predictor $owner.$col on outcome $(ch.name)"))
                    np = _normal_parameters(pr, "$(ch.name).$owner.$col")
                    x = haskey(derived, col) ? derived[col] : _numeric_column(table, col, E)
                    raw[col] = x
                    ovals = owner === :response ? Float64[] : _owned_values(identity, owner, col, x)
                    osgn = owner in (:person, :response) ? 1.0 : -1.0
                    evals = owner === :response ? Float64.(x) : osgn .* ovals[_owner_index(identity, owner)]
                    offset[] += 1
                    push!(terms, MixedOutcomeTerm(c, ch.name, owner, col, np.mean, np.sd, offset[], evals, ovals))
                    push!(crecs, col => np)
                end
                push!(opred_rec, owner => (; crecs...))
            end
        end
        ip = _normal_parameters(ospec.intercept, Symbol("$(ch.name)_intercept"))
        offset[] += 1
        push!(terms, MixedOutcomeTerm(c, ch.name, :response, nothing, ip.mean, ip.sd, offset[], ones(Float64, E), Float64[]))
        push!(out_specs_rec, ch.name => _serialize_outcome_channel(ch, ip, (; opred_rec...)))
    end

    pop_rec = (;(ob.name => _serialize_mixed_owner(ob, out_names) for ob in owner_blocks)...)
    spec = (; outcomes = (; out_specs_rec...), population = pop_rec, predictors = (; top_pred_rec...))
    dec === nothing || (spec = merge(spec, (; decomposition = dec)))
    alloc = mixed_allocation(owner_blocks, channels, terms, p_idx, p_lev, blocks, E)
    MixedOutcomeTarget(raw, columns, p_idx, p_lev, blocks, owner_blocks, channels, terms, spec, groups, offset[], alloc)
end

function _serialize_loading_entry(e::MixedLoadingEntry)
    e.kind === :fixed ? (; kind = :fixed, value = e.value) : (; kind = e.kind, mean = e.mean, sd = e.sd)
end

function _deserialize_loading_entry(r)
    r.kind === :fixed ? r.value : r.kind === :lognormal ? D.LogNormal(r.mean, r.sd) : D.Normal(r.mean, r.sd)
end

function _serialize_mixed_owner(ob::MixedOwnerBlock, out_names::Vector{Symbol})
    sds = [(ob.hyps[d] == 0 ? (; kind = :fixed, sd = ob.sds_fixed[d]) : (; kind = :lognormal, logmean = ob.logmeans[d], logsd = ob.logsds[d])) for d in 1:ob.D_dim]
    loads = [_serialize_loading_entry(ob.loadings[c, d]) for c in 1:size(ob.loadings, 1), d in 1:ob.D_dim]
    (; declaration_kind = ob.declaration_kind, dim_names = copy(ob.dim_names), sds,
       corr_kind = ob.corr_kind, corr_eta = ob.corr_eta, loadings = [loads[c, :] for c in axes(loads, 1)])
end

function _deserialize_mixed_owner(r)
    sd_val(s) = s.kind === :fixed ? s.sd : D.LogNormal(s.logmean, s.logsd)
    M = length(r.loadings); D_dim = length(r.dim_names)
    lmat = [_deserialize_loading_entry(r.loadings[c][d]) for c in 1:M, d in 1:D_dim]
    if Symbol(r.declaration_kind) === :shared_scalar
        return sd_val(only(r.sds))
    elseif Symbol(r.declaration_kind) === :loaded_1d
        return (; sd = sd_val(only(r.sds)), loadings = vec(lmat))
    end
    sds_nt = (;(Symbol(dname) => sd_val(s) for (dname, s) in zip(r.dim_names, r.sds))...)
    corr = Symbol(r.corr_kind) === :lkj ? D.LKJ(D_dim, r.corr_eta) : 0.0
    (; sds = sds_nt, correlation = corr, loadings = lmat)
end

function _serialize_outcome_channel(ch::MixedOutcomeChannel, ip, opreds)
    base = (; family = ch.family, score = ch.score_col, direction = ch.direction, version = ch.version, intercept = ip, predictors = opreds)
    if ch.family === :ordinal
        return merge(base, (; categories = copy(ch.categories), step_sd = ch.step_sd))
    elseif ch.family === :zero_one_inflated_beta
        return merge(base, (; bounds = ch.bounds,
            precision = (; kind = :lognormal, logmean = ch.prec_logmean, logsd = ch.prec_logsd),
            endpoint_logit = (; mean = ch.ep_mean, sd = ch.ep_sd),
            upper_logit = (; mean = ch.up_mean, sd = ch.up_sd)))
    elseif ch.family === :beta_binomial
        return merge(base, (; trials = ch.trials_col, precision = (; kind = :lognormal, logmean = ch.prec_logmean, logsd = ch.prec_logsd)))
    else
        return merge(base, (; trials = ch.trials_col))
    end
end

function _deserialize_outcome_channel(r)
    ip = D.Normal(r.intercept.mean, r.intercept.sd)
    opreds = (;(k => (;(c => D.Normal(v.mean, v.sd) for (c, v) in pairs(cols))...) for (k, cols) in pairs(r.predictors))...)
    kw = Pair{Symbol,Any}[:family => Symbol(r.family), :score => Symbol(r.score), :direction => Symbol(r.direction), :intercept => ip]
    r.version === nothing || push!(kw, :version => String(r.version))
    isempty(opreds) || push!(kw, :predictors => opreds)
    fam = Symbol(r.family)
    if fam === :ordinal
        push!(kw, :categories => collect(Int, r.categories), :step_sd => Float64(r.step_sd))
    elseif fam === :zero_one_inflated_beta
        push!(kw, :bounds => (Float64(r.bounds[1]), Float64(r.bounds[2])),
            :precision => D.LogNormal(r.precision.logmean, r.precision.logsd),
            :endpoint_logit => D.Normal(r.endpoint_logit.mean, r.endpoint_logit.sd),
            :upper_logit => D.Normal(r.upper_logit.mean, r.upper_logit.sd))
    elseif fam === :beta_binomial
        push!(kw, :trials => Symbol(r.trials), :precision => D.LogNormal(r.precision.logmean, r.precision.logsd))
    else
        push!(kw, :trials => Symbol(r.trials))
    end
    (; kw...)
end

function coordinates(t::MixedOutcomeTarget, q::AbstractVector{<:Real})
    _check(t, q); Z = promote_type(Float64, eltype(q))
    M = length(t.outcomes); lv = zero(Z)

    owner_vals = Dict{Symbol,NamedTuple}()
    for ob in t.owners
        L_o = length(ob.levels); D_dim = ob.D_dim
        sds = Vector{Z}(undef, D_dim)
        for d in 1:D_dim
            s = ob.hyps[d] == 0 ? Z(ob.sds_fixed[d]) : exp(ob.logmeans[d] + ob.logsds[d] * q[ob.hyps[d]])
            isfinite(s) && s > zero(Z) || throw(ArgumentError("unrepresentable SD for $(ob.name)"))
            sds[d] = s
            lv += L_o * log(s) + (ob.hyps[d] == 0 ? zero(Z) : log(ob.logsds[d]) + log(s))
        end
        Lmat, log_diag_sum, log_corr_jac = D_dim == 1 ? (ones(Z, 1, 1), zero(Z), zero(Z)) : _cholesky_cpc(q, ob.corr_raw, D_dim)
        lv += L_o * log_diag_sum + log_corr_jac
        Rmat = Lmat * transpose(Lmat)
        corrs = Z[Rmat[i, j] for i in 2:D_dim for j in 1:(i - 1)]

        b_lat = zeros(Z, L_o, D_dim)
        for d in 1:D_dim
            for m in 1:d
                b_lat[:, d] .+= Lmat[d, m] .* view(q, ob.raws[m])
            end
            b_lat[:, d] .*= sds[d]
        end

        Lam = Matrix{Z}(undef, M, D_dim)
        for d in 1:D_dim, c in 1:M
            le = ob.loadings[c, d]
            if le.kind === :fixed
                Lam[c, d] = Z(le.value)
            elseif le.kind === :normal
                Lam[c, d] = le.mean + le.sd * q[le.raw]
                lv += log(le.sd)
            else
                val = exp(le.mean + le.sd * q[le.raw])
                isfinite(val) && val > zero(Z) || throw(ArgumentError("unrepresentable positive loading"))
                Lam[c, d] = val
                lv += log(le.sd) + log(val)
            end
        end
        projected = b_lat * transpose(Lam) # L_o x M (unsigned; sign applied in linear predictor)
        owner_vals[ob.name] = (; latent = b_lat, projected, sds, L = Lmat, R = Rmat, correlations = corrs, loadings = Lam)
    end

    coefs = Z[tm.mean + tm.sd * q[tm.raw] for tm in t.terms]
    for tm in t.terms
        lv += log(tm.sd)
    end

    out_vals = Vector{NamedTuple}(undef, M)
    for (c, ch) in enumerate(t.outcomes)
        if ch.family === :ordinal
            H = length(ch.categories) - 1
            tau = H > 1 ? ch.step_scale .* N._zero_sum(view(q, ch.step_raw)) : zeros(Z, 1)
            H > 1 && (lv += length(ch.step_raw) * log(ch.step_scale))
            out_vals[c] = (; family = :ordinal, steps = tau)
        elseif ch.family === :zero_one_inflated_beta
            prec = exp(ch.prec_logmean + ch.prec_logsd * q[ch.prec_raw])
            isfinite(prec) && prec > zero(Z) || throw(ArgumentError("unrepresentable ZOIB precision for $(ch.name)"))
            ep = ch.ep_mean + ch.ep_sd * q[ch.ep_raw]
            up = ch.up_mean + ch.up_sd * q[ch.up_raw]
            lv += log(ch.prec_logsd) + log(prec) + log(ch.ep_sd) + log(ch.up_sd)
            out_vals[c] = (; family = :zero_one_inflated_beta, precision = prec, endpoint_logit = ep, upper_logit = up,
                endpoint_probability = _sigmoid(ep), upper_probability = _sigmoid(up))
        elseif ch.family === :beta_binomial
            prec = exp(ch.prec_logmean + ch.prec_logsd * q[ch.prec_raw])
            isfinite(prec) && prec > zero(Z) || throw(ArgumentError("unrepresentable beta-binomial precision for $(ch.name)"))
            lv += log(ch.prec_logsd) + log(prec)
            out_vals[c] = (; family = :beta_binomial, precision = prec)
        else
            out_vals[c] = (; family = :binomial)
        end
    end
    (; owners = owner_vals, coefficients = coefs, outcomes = out_vals, log_volume = lv,
       measure = :mixed_outcome_owner_factors_loadings_coefficients_and_family_parameters)
end

function logprior(t::MixedOutcomeTarget, q)
    _check(t, q); Z = promote_type(Float64, eltype(q))
    half_log2pi = Z(log(2pi) / 2)
    lp = -length(q) * half_log2pi - sum(abs2, q) / 2
    for ob in t.owners
        isempty(ob.corr_raw) && continue
        for (k, idx) in enumerate(ob.corr_raw)
            a = q[idx]
            lp += a^2 / 2 + half_log2pi + ob.alphas[k] * _logsech2(a) - ob.logbetas[k]
        end
    end
    lp
end

function prior_draw(t::MixedOutcomeTarget; seed = 1)
    seed isa Integer && !(seed isa Bool) && 0 <= seed <= typemax(Int) || throw(ArgumentError("invalid seed"))
    _mixed_prior_draw(t, MersenneTwister(Int(seed)))
end

function _mixed_prior_draw(t::MixedOutcomeTarget, rng::AbstractRNG)
    q = randn(rng, t.dimension)
    for ob in t.owners
        isempty(ob.corr_raw) && continue
        for (k, idx) in enumerate(ob.corr_raw)
            alpha = ob.alphas[k]
            rho = 2 * rand(rng, D.Beta(alpha, alpha)) - 1
            abs(rho) < 1 || throw(ArgumentError("LKJ draw rounded to boundary; review correlation prior"))
            q[idx] = atanh(rho)
        end
    end
    q
end

function _mixed_eta_matrix(t::MixedOutcomeTarget, v)
    E = length(t.person); M = length(t.outcomes)
    Z = eltype(v.coefficients)
    eta = zeros(Z, E, M)
    for ob in t.owners
        proj = v.owners[ob.name].projected
        sgn = ob.sign
        ix = ob.index
        @inbounds for c in 1:M, e in 1:E
            eta[e, c] += sgn * proj[ix[e], c]
        end
    end
    for (ti, tm) in enumerate(t.terms)
        c = tm.outcome_idx; bval = v.coefficients[ti]; xv = tm.values
        @inbounds for e in 1:E
            eta[e, c] += bval * xv[e]
        end
    end
    for (c, ch) in enumerate(t.outcomes)
        ch.dir_sign == 1.0 && continue
        @inbounds for e in 1:E
            eta[e, c] = -eta[e, c]
        end
    end
    eta
end

function _ordinal_cell_and_grad!(a::Vector{Z}, gs::Vector{Z}, y_idx::Int, eta::Z, tau::AbstractVector{Z}) where {Z}
    K = length(a); H = K - 1
    a[1] = zero(Z)
    @inbounds for h in 1:H
        a[h + 1] = a[h] + eta - tau[h]
    end
    mx = a[1]
    @inbounds for k in 2:K
        a[k] > mx && (mx = a[k])
    end
    isfinite(mx) || return (Z(-Inf), Z(NaN))
    s = zero(Z)
    @inbounds for k in 1:K
        s += exp(a[k] - mx)
    end
    lse = mx + log(s)
    lp = a[y_idx] - lse
    exp_k = zero(Z)
    @inbounds for k in 1:K
        pk = exp(a[k] - lse)
        a[k] = pk
        exp_k += (k - 1) * pk
    end
    de = Z(y_idx - 1) - exp_k
    tail = zero(Z)
    @inbounds for h in H:-1:1
        tail += a[h + 1]
        gs[h] += tail - (y_idx > h ? one(Z) : zero(Z))
    end
    lp, de
end

function L.logdensity_and_gradient(t::MixedOutcomeTarget, q::AbstractVector{<:Real})
    _check(t, q; finite = false); Z = promote_type(Float64, eltype(q))
    d_total = length(q)
    reject() = (-Z(Inf), fill(Z(NaN), d_total))
    all(isfinite, q) || return reject()

    E = length(t.person); M = length(t.outcomes)
    half_log2pi = Z(log(2pi) / 2)
    lp = -d_total * half_log2pi - sum(abs2, q) / 2
    grad = -Z.(q)

    # 1. Forward owner transformations & correlation priors
    n_owners = length(t.owners)
    o_sds = Vector{Vector{Z}}(undef, n_owners)
    o_u = Vector{Vector{Z}}(undef, n_owners)
    o_c = Vector{Vector{Z}}(undef, n_owners)
    o_L = Vector{Matrix{Z}}(undef, n_owners)
    o_w = Vector{Matrix{Z}}(undef, n_owners)
    o_b = Vector{Matrix{Z}}(undef, n_owners)
    o_Lam = Vector{Matrix{Z}}(undef, n_owners)
    o_proj = Vector{Matrix{Z}}(undef, n_owners)
    o_hbar = Vector{Matrix{Z}}(undef, n_owners)

    for (oi, ob) in enumerate(t.owners)
        L_o = length(ob.levels); D_dim = ob.D_dim
        sds = Vector{Z}(undef, D_dim)
        for d in 1:D_dim
            s = ob.hyps[d] == 0 ? Z(ob.sds_fixed[d]) : exp(ob.logmeans[d] + ob.logsds[d] * q[ob.hyps[d]])
            isfinite(s) && s > zero(Z) || return reject()
            sds[d] = s
        end
        o_sds[oi] = sds

        nc = length(ob.corr_raw)
        u_vec = Vector{Z}(undef, nc); c_vec = Vector{Z}(undef, nc)
        Lmat = zeros(Z, D_dim, D_dim)
        for d in 1:D_dim; Lmat[d, d] = one(Z); end
        if nc > 0
            k = 0
            for i in 2:D_dim
                log_rem = zero(Z)
                for j in 1:(i - 1)
                    k += 1; idx = ob.corr_raw[k]; a = q[idx]
                    u_ij = tanh(a); ls = _logsech2(a); c_ij = exp(ls / 2)
                    u_vec[k] = u_ij; c_vec[k] = c_ij
                    Lmat[i, j] = u_ij * exp(log_rem / 2)
                    log_rem += ls
                    al = ob.alphas[k]
                    lp += a^2 / 2 + half_log2pi + al * ls - Z(ob.logbetas[k])
                    grad[idx] = -2 * al * u_ij # replaces -q[idx] prior derivative cleanly
                end
                diag_ii = exp(log_rem / 2)
                isfinite(diag_ii) && diag_ii > zero(Z) || return reject()
                Lmat[i, i] = diag_ii
            end
        end
        o_u[oi] = u_vec; o_c[oi] = c_vec; o_L[oi] = Lmat

        w_mat = zeros(Z, L_o, D_dim); b_mat = zeros(Z, L_o, D_dim)
        for d in 1:D_dim
            @inbounds for m in 1:d
                lm = Lmat[d, m]; z_col = view(q, ob.raws[m])
                for j in 1:L_o
                    w_mat[j, d] += lm * z_col[j]
                end
            end
            sd_d = sds[d]
            @inbounds for j in 1:L_o
                b_mat[j, d] = sd_d * w_mat[j, d]
            end
        end
        o_w[oi] = w_mat; o_b[oi] = b_mat

        Lam = Matrix{Z}(undef, M, D_dim)
        for d in 1:D_dim, c in 1:M
            le = ob.loadings[c, d]
            if le.kind === :fixed
                Lam[c, d] = Z(le.value)
            elseif le.kind === :normal
                Lam[c, d] = le.mean + le.sd * q[le.raw]
            else
                val = exp(le.mean + le.sd * q[le.raw])
                isfinite(val) && val > zero(Z) || return reject()
                Lam[c, d] = val
            end
        end
        o_Lam[oi] = Lam
        o_proj[oi] = (b_mat * transpose(Lam)) .* ob.sign
        o_hbar[oi] = zeros(Z, L_o, M)
    end

    # 2. Streamed event-by-outcome likelihoods & reverse accumulation (zero E x M heap allocation!)
    coefs = Z[tm.mean + tm.sd * q[tm.raw] for tm in t.terms]
    term_scores = zeros(Z, length(t.terms))
    cterms_by_out = [findall(tm -> tm.outcome_idx == c, t.terms) for c in 1:M]

    for (c, ch) in enumerate(t.outcomes)
        dsgn = ch.dir_sign
        cterms = cterms_by_out[c]
        if ch.family === :ordinal
            K = length(ch.categories); H = K - 1
            tau = H > 1 ? ch.step_scale .* N._zero_sum(view(q, ch.step_raw)) : zeros(Z, 1)
            a_buf = zeros(Z, K); gs = zeros(Z, H)
            @inbounds for e in ch.obs_rows
                eta_ec = zero(Z)
                for oi in 1:n_owners
                    eta_ec += o_proj[oi][t.owners[oi].index[e], c]
                end
                for ti in cterms
                    eta_ec += coefs[ti] * t.terms[ti].values[e]
                end
                l_cell, de = _ordinal_cell_and_grad!(a_buf, gs, ch.y_ord[e], dsgn * eta_ec, tau)
                isfinite(l_cell) || return reject()
                lp += l_cell
                ge = dsgn * de
                for oi in 1:n_owners
                    o_hbar[oi][t.owners[oi].index[e], c] += ge
                end
                for ti in cterms
                    term_scores[ti] += ge * t.terms[ti].values[e]
                end
            end
            H > 1 && S._helmert_pullback!(grad, ch.step_raw, gs, ch.step_scale)
        elseif ch.family === :zero_one_inflated_beta
            prec = exp(ch.prec_logmean + ch.prec_logsd * q[ch.prec_raw])
            isfinite(prec) && prec > zero(Z) || return reject()
            ep = ch.ep_mean + ch.ep_sd * q[ch.ep_raw]
            up = ch.up_mean + ch.up_sd * q[ch.up_raw]
            gp = zero(Z); gz = zero(Z); gh = zero(Z)
            @inbounds for e in ch.obs_rows
                eta_ec = zero(Z)
                for oi in 1:n_owners
                    eta_ec += o_proj[oi][t.owners[oi].index[e], c]
                end
                for ti in cterms
                    eta_ec += coefs[ti] * t.terms[ti].values[e]
                end
                l_cell, de, dp, dz, dh = _bounded_cell_scalar(ch.y_zoib[e], dsgn * eta_ec, prec, ep, up, ch.log_width)
                isfinite(l_cell) || return reject()
                lp += l_cell
                ge = dsgn * de
                gp += dp; gz += dz; gh += dh
                for oi in 1:n_owners
                    o_hbar[oi][t.owners[oi].index[e], c] += ge
                end
                for ti in cterms
                    term_scores[ti] += ge * t.terms[ti].values[e]
                end
            end
            grad[ch.prec_raw] += ch.prec_logsd * gp
            grad[ch.ep_raw] += ch.ep_sd * gz
            grad[ch.up_raw] += ch.up_sd * gh
        else
            bb = ch.family === :beta_binomial
            prec = if bb
                pr = exp(ch.prec_logmean + ch.prec_logsd * q[ch.prec_raw])
                isfinite(pr) && pr > zero(Z) || return reject()
                pr
            else
                nothing
            end
            gp = zero(Z)
            @inbounds for e in ch.obs_rows
                eta_ec = zero(Z)
                for oi in 1:n_owners
                    eta_ec += o_proj[oi][t.owners[oi].index[e], c]
                end
                for ti in cterms
                    eta_ec += coefs[ti] * t.terms[ti].values[e]
                end
                l_cell, de, dp = count_cell(ch.y_count[e], ch.trials[e], dsgn * eta_ec, prec, ch.logchoose[e])
                isfinite(l_cell) || return reject()
                lp += l_cell
                ge = dsgn * de
                gp += dp
                for oi in 1:n_owners
                    o_hbar[oi][t.owners[oi].index[e], c] += ge
                end
                for ti in cterms
                    term_scores[ti] += ge * t.terms[ti].values[e]
                end
            end
            bb && (grad[ch.prec_raw] += ch.prec_logsd * gp)
        end
    end

    # 3. Pullback into terms and owner blocks
    for (ti, tm) in enumerate(t.terms)
        grad[tm.raw] += tm.sd * term_scores[ti]
    end

    for (oi, ob) in enumerate(t.owners)
        L_o = length(ob.levels); D_dim = ob.D_dim
        hbar = o_hbar[oi]
        Lam = o_Lam[oi]; b_mat = o_b[oi]; w_mat = o_w[oi]; sds = o_sds[oi]; Lmat = o_L[oi]
        sgn = ob.sign

        # Free loading gradients
        for d in 1:D_dim, c in 1:M
            le = ob.loadings[c, d]
            le.kind === :fixed && continue
            glam = zero(Z)
            @inbounds for j in 1:L_o
                glam += b_mat[j, d] * hbar[j, c]
            end
            glam *= sgn
            if le.kind === :normal
                grad[le.raw] += le.sd * glam
            else
                grad[le.raw] += le.sd * Lam[c, d] * glam
            end
        end

        # b_bar = sgn * hbar * Lam (L_o x D_dim)
        b_bar = (hbar * Lam) .* sgn
        w_bar = Matrix{Z}(undef, L_o, D_dim)
        for d in 1:D_dim
            if ob.hyps[d] > 0
                dot_bd = zero(Z)
                @inbounds for j in 1:L_o
                    dot_bd += b_mat[j, d] * b_bar[j, d]
                end
                grad[ob.hyps[d]] += ob.logsds[d] * dot_bd
            end
            sd_d = sds[d]
            @inbounds for j in 1:L_o
                w_bar[j, d] = sd_d * b_bar[j, d]
            end
        end

        # Z_bar = w_bar * Lmat (for lower-triangular Lmat, Z_bar[:, m] = sum_{d=m}^D w_bar[:, d] * Lmat[d, m])
        for m in 1:D_dim
            r_m = ob.raws[m]
            @inbounds for d in m:D_dim
                lm = Lmat[d, m]
                for j in 1:L_o
                    grad[r_m[j]] += lm * w_bar[j, d]
                end
            end
        end

        # CPC Cholesky pullback when corr_kind === :lkj
        if !isempty(ob.corr_raw)
            u_vec = o_u[oi]; c_vec = o_c[oi]
            Lbar = zeros(Z, D_dim, D_dim)
            for i in 2:D_dim, m in 1:i
                z_col = view(q, ob.raws[m]); s_lm = zero(Z)
                @inbounds for j in 1:L_o
                    s_lm += w_bar[j, i] * z_col[j]
                end
                Lbar[i, m] = s_lm
            end
            k_base = 0
            for i in 2:D_dim
                n_row = i - 1
                # Compute prefix products P_{i, 1..n_row}: P_1 = 1, P_{j+1} = P_j * c_{ij}
                P_row = Vector{Z}(undef, n_row)
                P_row[1] = one(Z)
                for j in 1:(n_row - 1)
                    P_row[j + 1] = P_row[j] * c_vec[k_base + j]
                end
                rem_grad = Lbar[i, i]
                for j in n_row:-1:1
                    kk = k_base + j
                    u_ij = u_vec[kk]; c_ij = c_vec[kk]; P_ij = P_row[j]
                    grad[ob.corr_raw[kk]] += P_ij * c_ij * (Lbar[i, j] * c_ij - rem_grad * u_ij)
                    rem_grad = rem_grad * c_ij + Lbar[i, j] * u_ij
                end
                k_base += n_row
            end
        end
    end

    isfinite(lp) && all(isfinite, grad) ? (lp, grad) : reject()
end

L.logdensity(t::MixedOutcomeTarget, q::AbstractVector{<:Real}) = first(L.logdensity_and_gradient(t, q))

function pointwise(t::MixedOutcomeTarget, q)
    v = coordinates(t, q); eta = _mixed_eta_matrix(t, v)
    E = length(t.person); Z = eltype(eta)
    out = zeros(Z, E)
    for (c, ch) in enumerate(t.outcomes)
        ov = v.outcomes[c]
        if ch.family === :ordinal
            K = length(ch.categories); a_buf = zeros(Z, K); gs = zeros(Z, max(1, K - 1))
            for e in ch.obs_rows
                l_cell, _ = _ordinal_cell_and_grad!(a_buf, gs, ch.y_ord[e], eta[e, c], ov.steps)
                out[e] += l_cell
            end
        elseif ch.family === :zero_one_inflated_beta
            for e in ch.obs_rows
                l_cell, _, _, _, _ = _bounded_cell_scalar(ch.y_zoib[e], eta[e, c], ov.precision, ov.endpoint_logit, ov.upper_logit, ch.log_width)
                out[e] += l_cell
            end
        else
            prec = ch.family === :beta_binomial ? ov.precision : nothing
            for e in ch.obs_rows
                l_cell, _, _ = count_cell(ch.y_count[e], ch.trials[e], eta[e, c], prec, ch.logchoose[e])
                out[e] += l_cell
            end
        end
    end
    out
end

function names(t::MixedOutcomeTarget, scale)
    scale in (:raw, :model) || throw(ArgumentError("scale must be :raw or :model"))
    out = String[]
    out_names = [ch.name for ch in t.outcomes]
    if scale === :raw
        for ob in t.owners
            for d in 1:ob.D_dim
                dtag = ob.D_dim == 1 ? "" : ",$(ob.dim_names[d])"
                append!(out, ["$(ob.name)$dtag.white[$j]" for j in 1:length(ob.levels)])
            end
            for d in 1:ob.D_dim
                ob.hyps[d] > 0 && push!(out, ob.D_dim == 1 ? "log_sd[$(ob.name)].white" : "log_sd[$(ob.name),$(ob.dim_names[d])].white")
            end
            if !isempty(ob.corr_raw)
                k = 0
                for i in 2:ob.D_dim, j in 1:(i - 1)
                    k += 1; push!(out, "corr_cpc[$(ob.name),$(ob.dim_names[j]),$(ob.dim_names[i])].white")
                end
            end
            for d in 1:ob.D_dim, c in 1:length(out_names)
                le = ob.loadings[c, d]
                le.kind === :fixed && continue
                push!(out, "loading[$(ob.name),$(out_names[c]),$(ob.dim_names[d])].white")
            end
        end
        for ch in t.outcomes
            if ch.family === :ordinal
                append!(out, ["steps[$(ch.name),$j].white" for j in 1:length(ch.step_raw)])
            elseif ch.family === :zero_one_inflated_beta
                push!(out, "log_precision[$(ch.name)].white", "endpoint_logit[$(ch.name)].white", "upper_logit[$(ch.name)].white")
            elseif ch.family === :beta_binomial
                push!(out, "log_precision[$(ch.name)].white")
            end
        end
        for tm in t.terms
            push!(out, _mixed_term_name(tm) * ".white")
        end
        return out
    end

    # Model-space names
    for ob in t.owners
        for d in 1:ob.D_dim
            dtag = ob.D_dim == 1 ? "" : ",$(ob.dim_names[d])"
            append!(out, ["$(ob.name)[$(repr(id))$dtag]" for id in ob.levels])
        end
    end
    for tm in t.terms
        push!(out, _mixed_term_name(tm))
    end
    for ob in t.owners
        for d in 1:ob.D_dim
            push!(out, ob.D_dim == 1 ? "residual_sd[$(ob.name)]" : "residual_sd[$(ob.name),$(ob.dim_names[d])]")
        end
        if ob.D_dim >= 2
            for i in 2:ob.D_dim, j in 1:(i - 1)
                push!(out, "correlation[$(ob.name),$(ob.dim_names[j]),$(ob.dim_names[i])]")
            end
        end
        for d in 1:ob.D_dim, c in 1:length(out_names)
            le = ob.loadings[c, d]
            (ob.declaration_kind === :loaded_1d || le.kind !== :fixed) &&
                push!(out, "loading[$(ob.name),$(out_names[c]),$(ob.dim_names[d])]")
        end
    end
    for ch in t.outcomes
        if ch.family === :ordinal
            append!(out, ["steps[$(ch.name),$j]" for j in 1:(length(ch.categories) - 1)])
        elseif ch.family === :zero_one_inflated_beta
            push!(out, "precision[$(ch.name)]", "endpoint_logit[$(ch.name)]", "upper_logit[$(ch.name)]")
        elseif ch.family === :beta_binomial
            push!(out, "precision[$(ch.name)]")
        end
    end
    out
end

_mixed_term_name(tm::MixedOutcomeTerm) = tm.column === nothing ? "intercept[$(tm.outcome)]" : "coefficient[$(tm.outcome),$(tm.owner),$(tm.column)]"

function record(t::MixedOutcomeTarget)
    (; schema = MIXED_SCHEMA, table = deepcopy(t.table), columns = deepcopy(t.columns),
       levels = (; person = deepcopy(t.people), facets = (;(b.name => deepcopy(b.levels) for b in t.facets)...)),
       specification = deepcopy(t.specification),
       coordinates = any(ob -> !isempty(ob.corr_raw), t.owners) ? :white_normal_and_cpc_correlation : :white_standard_normal,
       measure = :mixed_outcome_event_joint_density_and_mass)
end

function restore_mixed(r)
    r.schema == MIXED_SCHEMA &&
        r.coordinates in (:white_standard_normal, :white_normal_and_cpc_correlation) &&
        r.measure === :mixed_outcome_event_joint_density_and_mass ||
        throw(ArgumentError("unsupported mixed-outcome design record"))
    s = r.specification
    outs = (;(k => _deserialize_outcome_channel(v) for (k, v) in pairs(s.outcomes))...)
    pop = (;(k => _deserialize_mixed_owner(v) for (k, v) in pairs(s.population))...)
    preds = (;(k => (;(c => (hasproperty(v, :kind) && Symbol(v.kind) === :by_outcome ?
        (;(ok => (ov === nothing ? nothing : D.Normal(ov.mean, ov.sd)) for (ok, ov) in pairs(v.outcomes))...) :
        D.Normal(v.mean, v.sd)) for (c, v) in pairs(cols))...) for (k, cols) in pairs(s.predictors))...)
    rules = hasproperty(s, :decomposition) ? (;(d.source => (; between = d.between, within = d.within) for d in s.decomposition.rules)...) : nothing
    t = mixed_outcome_model(r.table; outcomes = outs, person = r.columns.person, facets = r.columns.facets,
        population = pop, predictors = preds, decompose = rules, levels = r.levels,
        performance = r.columns.performance, assessment = r.columns.assessment)
    B._cache_hash(record(t)) == B._cache_hash(r) || throw(ArgumentError("mixed-outcome design record is not reproducible"))
    t
end

function response_patterns(t::MixedOutcomeTarget)
    E = length(t.person); M = length(t.outcomes); warnings = String[]
    mask_counts = Dict{Vector{Symbol},Int}()
    for e in 1:E
        pat = Symbol[ch.name for ch in t.outcomes if ch.observed[e]]
        mask_counts[pat] = get(mask_counts, pat, 0) + 1
    end
    masks = [(; outcomes = k, count = mask_counts[k]) for k in sort!(collect(keys(mask_counts)); by = string)]
    length(masks) > 1 && push!(warnings, "Partial-outcome events present across $(length(masks)) observation patterns; log-likelihood sums observed outcomes per event under missing-at-random conditioning.")

    outcome_summaries = NamedTuple[]
    for ch in t.outcomes
        n_obs = length(ch.obs_rows)
        if ch.family === :ordinal
            counts = [count(e -> ch.y_ord[e] == k, ch.obs_rows) for k in eachindex(ch.categories)]
            unused = [ch.categories[k] for k in eachindex(ch.categories) if counts[k] == 0]
            isempty(unused) || push!(warnings, "Outcome $(ch.name) has unobserved declared categories $unused; proper step priors retain full category support.")
            push!(outcome_summaries, (; outcome = ch.name, family = :ordinal, n_observed = n_obs, categories = copy(ch.categories), category_counts = counts, unused_categories = unused))
        elseif ch.family === :zero_one_inflated_beta
            ys = ch.y_zoib[ch.obs_rows]
            n_lo = count(==(0.0), ys); n_hi = count(==(1.0), ys); n_int = n_obs - n_lo - n_hi
            n_int == 0 && push!(warnings, "Outcome $(ch.name) has zero interior observations; ZOIB interior mean/precision rely on priors.")
            (n_lo + n_hi == 0) && push!(warnings, "Outcome $(ch.name) has zero boundary observations; ZOIB endpoint/upper logits rely on priors.")
            (n_lo + n_hi > 0 && (n_lo == 0 || n_hi == 0)) && push!(warnings, "Outcome $(ch.name) observes only one boundary endpoint; upper_logit is weakly informed.")
            push!(outcome_summaries, (; outcome = ch.name, family = :zero_one_inflated_beta, n_observed = n_obs, bounds = ch.bounds, lower = n_lo, upper = n_hi, interior = n_int))
        else
            ys = ch.y_count[ch.obs_rows]; ns = ch.trials[ch.obs_rows]
            nz = count(iszero, ys); nf = count(ys .== ns); all_bin = all(==(1), ns)
            ch.family === :beta_binomial && all_bin && push!(warnings, "Outcome $(ch.name) has all trial counts equal to 1: beta-binomial precision is prior-only.")
            push!(outcome_summaries, (; outcome = ch.name, family = ch.family, n_observed = n_obs, zero = nz, perfect = nf, trial_counts = sort(unique(ns))))
        end
    end
    (; n_events = E, n_outcomes = M, observation_masks = masks, outcomes = outcome_summaries, warnings)
end

warn_patterns(t::MixedOutcomeTarget) = foreach(w -> @warn(w), response_patterns(t).warnings)

function design(t::MixedOutcomeTarget)
    pat = response_patterns(t)
    (; n_events = length(t.person), n_outcomes = length(t.outcomes),
       outcomes = [(; name = ch.name, family = ch.family, score = ch.score_col, direction = ch.direction, version = ch.version, n_observed = length(ch.obs_rows)) for ch in t.outcomes],
       n_persons = length(t.people), n_facets = length(t.facets) + 1, n_parameters = t.dimension,
       owners = [(; name = ob.name, levels = length(ob.levels), dimensions = ob.D_dim, dim_names = copy(ob.dim_names), correlation = ob.corr_kind) for ob in t.owners],
       allocation = t.allocation, grouping = t.groups, response_patterns = pat,
       warnings = vcat(pat.warnings, [
           "Experimental mixed-outcome joint model: conditional within-event independence given declared owner/performance effects; verify with paired joint PPC.",
           "Different outcome families use distinct link scales and measures (ordinal mass, continuous ZOIB density with endpoint atoms, count mass); raw coefficients are not directly commensurable across families.",
           "Distinct architectural scope from Concurrent (fixed 9/9/2 Sekiguchi protocol + Plackett copula) and StarAssociation (ordinal-only star event association).",
       ]),
       scientific_acceptance = false)
end

function contract(t::MixedOutcomeTarget)
    (; schema = "bayesianmgmfrm.mixed_outcome_contract.v1",
       family = :mixed_outcome_joint_explanatory,
       status = :experimental_fitted_workflow,
       outcomes = [(; name = ch.name, family = ch.family, direction = ch.direction, version = ch.version) for ch in t.outcomes],
       owners = [(; name = ob.name, dimensions = ob.D_dim, dim_names = copy(ob.dim_names), correlation = ob.corr_kind, declaration = ob.declaration_kind) for ob in t.owners],
       multiplier = 1.0,
       within_event_dependence = :conditionally_independent_given_declared_owners,
       architectural_boundary = (;
           concurrent_three_outcome = :separate_fixed_9_9_2_sekiguchi_protocol_and_plackett_route,
           star_association = :separate_ordinal_only_star_event_association_route),
       prediction_modes = (:known_owners, :new_owners),
       zero_effect_new_owner_substitution = :refused,
       held_unit_integration = (:event, :performance),
       scientific_acceptance = false,
       record = record(t))
end

function stan_data(t::MixedOutcomeTarget)
    E = length(t.person); M = length(t.outcomes); O = length(t.owners); T_terms = length(t.terms)
    # Pack owner blocks, outcomes, and terms into flat integer/real arrays for `src/stan/mixed_outcomes.stan`
    owner_L = Int[length(ob.levels) for ob in t.owners]
    owner_D = Int[ob.D_dim for ob in t.owners]
    owner_sign = Float64[ob.sign for ob in t.owners]
    owner_index = hcat([ob.index for ob in t.owners]...) # E x O

    # Flatten per-(owner, d) slices: n_slices = sum(owner_D)
    slice_owner = Int[]; slice_dim = Int[]; slice_raw_start = Int[]; slice_L = Int[]
    slice_hyp = Int[]; slice_sd_fixed = Float64[]; slice_logmean = Float64[]; slice_logsd = Float64[]
    for (oi, ob) in enumerate(t.owners), d in 1:ob.D_dim
        push!(slice_owner, oi); push!(slice_dim, d)
        push!(slice_raw_start, first(ob.raws[d])); push!(slice_L, length(ob.levels))
        push!(slice_hyp, ob.hyps[d]); push!(slice_sd_fixed, ob.sds_fixed[d])
        push!(slice_logmean, ob.logmeans[d]); push!(slice_logsd, ob.logsds[d])
    end

    corr_owner = Int[]; corr_D = Int[]; corr_start = Int[]; corr_len = Int[]; corr_eta = Float64[]
    for (oi, ob) in enumerate(t.owners)
        ob.corr_kind === :lkj || continue
        push!(corr_owner, oi); push!(corr_D, ob.D_dim)
        push!(corr_start, first(ob.corr_raw)); push!(corr_len, length(ob.corr_raw))
        push!(corr_eta, ob.corr_eta)
    end

    # Loadings entries: O_total_entries = sum(M * D_dim)
    load_owner = Int[]; load_out = Int[]; load_dim = Int[]
    load_kind = Int[]; load_val = Float64[]; load_mean = Float64[]; load_sd = Float64[]; load_raw = Int[]
    for (oi, ob) in enumerate(t.owners), d in 1:ob.D_dim, c in 1:M
        le = ob.loadings[c, d]
        push!(load_owner, oi); push!(load_out, c); push!(load_dim, d)
        push!(load_kind, le.kind === :fixed ? 0 : le.kind === :normal ? 1 : 2)
        push!(load_val, le.value); push!(load_mean, le.mean); push!(load_sd, le.sd); push!(load_raw, le.raw)
    end

    # Outcomes metadata
    # family code: 1=ordinal, 2=zoib, 3=binomial, 4=beta_binomial
    out_fam = Int[]; out_dir = Float64[]; out_K = Int[]; out_step_scale = Float64[]; out_step_start = Int[]
    out_log_width = Float64[]; out_prec_lm = Float64[]; out_prec_ls = Float64[]; out_prec_raw = Int[]
    out_ep_m = Float64[]; out_ep_s = Float64[]; out_ep_raw = Int[]
    out_up_m = Float64[]; out_up_s = Float64[]; out_up_raw = Int[]
    Hstep_flat = Float64[]; Hstep_offset = Int[]; Hstep_rows = Int[]; Hstep_cols = Int[]
    obs_mask = zeros(Int, E, M)
    y_ord_mat = ones(Int, E, M)
    y_zoib_mat = fill(0.5, E, M)
    y_cnt_mat = zeros(Int, E, M)
    trials_mat = ones(Int, E, M)

    for (c, ch) in enumerate(t.outcomes)
        fc = ch.family === :ordinal ? 1 : ch.family === :zero_one_inflated_beta ? 2 : ch.family === :binomial ? 3 : 4
        push!(out_fam, fc); push!(out_dir, ch.dir_sign)
        K = ch.family === :ordinal ? length(ch.categories) : 2
        H = K - 1
        push!(out_K, K); push!(out_step_scale, ch.step_scale)
        push!(out_step_start, isempty(ch.step_raw) ? 0 : first(ch.step_raw))
        push!(Hstep_offset, length(Hstep_flat))
        if ch.family === :ordinal && H > 1
            Hmat = zeros(Float64, H, H - 1)
            for k in 1:(H - 1)
                Hmat[1:k, k] .= ch.step_scale / sqrt(k * (k + 1))
                Hmat[k + 1, k] = -k * ch.step_scale / sqrt(k * (k + 1))
            end
            append!(Hstep_flat, vec(Hmat))
            push!(Hstep_rows, H); push!(Hstep_cols, H - 1)
        else
            push!(Hstep_rows, 0); push!(Hstep_cols, 0)
        end
        push!(out_log_width, ch.log_width)
        push!(out_prec_lm, ch.prec_logmean); push!(out_prec_ls, ch.prec_logsd); push!(out_prec_raw, ch.prec_raw)
        push!(out_ep_m, ch.ep_mean); push!(out_ep_s, ch.ep_sd); push!(out_ep_raw, ch.ep_raw)
        push!(out_up_m, ch.up_mean); push!(out_up_s, ch.up_sd); push!(out_up_raw, ch.up_raw)
        for e in ch.obs_rows
            obs_mask[e, c] = 1
            ch.family === :ordinal && (y_ord_mat[e, c] = ch.y_ord[e])
            ch.family === :zero_one_inflated_beta && (y_zoib_mat[e, c] = ch.y_zoib[e])
            if ch.family in (:binomial, :beta_binomial)
                y_cnt_mat[e, c] = ch.y_count[e]; trials_mat[e, c] = ch.trials[e]
            end
        end
    end

    X_terms = hcat([tm.values for tm in t.terms]...) # E x T_terms
    Dict(
        "D" => t.dimension, "E" => E, "M" => M, "O" => O, "T" => T_terms,
        "owner_L" => owner_L, "owner_D" => owner_D, "owner_sign" => owner_sign, "owner_index" => owner_index,
        "N_slices" => length(slice_owner), "slice_owner" => slice_owner, "slice_dim" => slice_dim,
        "slice_raw_start" => slice_raw_start, "slice_L" => slice_L, "slice_hyp" => slice_hyp,
        "slice_sd_fixed" => slice_sd_fixed, "slice_logmean" => slice_logmean, "slice_logsd" => slice_logsd,
        "N_corr" => length(corr_owner), "corr_owner" => corr_owner, "corr_D" => corr_D,
        "corr_start" => corr_start, "corr_len" => corr_len, "corr_eta" => corr_eta,
        "N_load" => length(load_owner), "load_owner" => load_owner, "load_out" => load_out, "load_dim" => load_dim,
        "load_kind" => load_kind, "load_val" => load_val, "load_mean" => load_mean, "load_sd" => load_sd, "load_raw" => load_raw,
        "out_fam" => out_fam, "out_dir" => out_dir, "out_K" => out_K, "out_step_scale" => out_step_scale, "out_step_start" => out_step_start,
        "N_Hstep" => length(Hstep_flat), "Hstep_flat" => Hstep_flat, "Hstep_offset" => Hstep_offset, "Hstep_rows" => Hstep_rows, "Hstep_cols" => Hstep_cols,
        "out_log_width" => out_log_width, "out_prec_lm" => out_prec_lm, "out_prec_ls" => out_prec_ls, "out_prec_raw" => out_prec_raw,
        "out_ep_m" => out_ep_m, "out_ep_s" => out_ep_s, "out_ep_raw" => out_ep_raw,
        "out_up_m" => out_up_m, "out_up_s" => out_up_s, "out_up_raw" => out_up_raw,
        "obs_mask" => obs_mask, "y_ord" => y_ord_mat, "y_zoib" => y_zoib_mat, "y_cnt" => y_cnt_mat, "trials" => trials_mat,
        "term_out" => Int[tm.outcome_idx for tm in t.terms],
        "term_raw" => Int[tm.raw for tm in t.terms],
        "term_mean" => Float64[tm.mean for tm in t.terms],
        "term_sd" => Float64[tm.sd for tm in t.terms],
        "X_terms" => X_terms,
    )
end
