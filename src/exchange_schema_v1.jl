# Path-parameterized Exchange Schema v1.0 read-only loader, writer, validator,
# and cross-engine evaluator for `BayesianMGMFRM.ValidationSuite`.
#
# Included inside `module ValidationSuite` (`src/validation_suite.jl`).
# Zero hardcoded external filesystem paths: all study/case/run directories are
# passed explicitly by the caller, and bundled unit tests run on synthetic
# micro-fixtures created in temporary directories.

import SparseArrays

const EXCHANGE_SCHEMA_VERSION = "1.0"

const _EXCHANGE_FACETS_HEADER = (
    "facet", "element", "measure", "se",
    "infit_mnsq", "infit_z", "outfit_mnsq", "outfit_z", "extreme_flag",
)
const _EXCHANGE_STEPS_HEADER = ("criterion", "step", "measure", "se")
const _EXCHANGE_PERSON_HEADER = (
    "person", "measure", "se", "real_se", "fair_m",
    "infit_mnsq", "infit_z", "outfit_mnsq", "outfit_z", "extreme_flag", "score_method",
)
const _EXCHANGE_CONTRAST_HEADER = (
    "contrast_id", "target_rater", "group_a", "group_b",
    "estimate", "se", "stat", "df", "p_value", "ci_low", "ci_high", "method", "identifiable",
)

function _parse_csv_line(line::AbstractString)
    s = chomp(line)
    endswith(s, '\r') && (s = chop(s))
    fields = String[]
    buf = IOBuffer()
    in_quotes = false
    i = firstindex(s)
    last_i = lastindex(s)
    while i <= last_i
        c = s[i]
        if in_quotes
            if c == '"'
                nxt = nextind(s, i)
                if nxt <= last_i && s[nxt] == '"'
                    write(buf, '"')
                    i = nextind(s, nxt)
                    continue
                else
                    in_quotes = false
                end
            else
                write(buf, c)
            end
        else
            if c == '"'
                in_quotes = true
            elseif c == ','
                push!(fields, String(take!(buf)))
            else
                write(buf, c)
            end
        end
        i = nextind(s, i)
    end
    in_quotes && throw(ArgumentError("unterminated quote in CSV line: $(repr(line))"))
    push!(fields, String(take!(buf)))
    return fields
end

function _read_simple_csv(path::AbstractString)
    isfile(path) || throw(ArgumentError("CSV file does not exist: $path"))
    header = nothing
    rows = Vector{Vector{String}}()
    for raw_line in eachline(path)
        stripped = strip(raw_line)
        isempty(stripped) && continue
        cols = _parse_csv_line(raw_line)
        if header === nothing
            header = String[strip(c) for c in cols]
        else
            length(cols) == length(header) || throw(ArgumentError(
                "CSV column count mismatch in $path: got $(length(cols)), expected $(length(header))"))
            push!(rows, cols)
        end
    end
    header === nothing && throw(ArgumentError("CSV file is empty: $path"))
    return (; header, rows)
end

_csv_escape(x::AbstractString) = (occursin(',', x) || occursin('"', x) || occursin('\n', x)) ?
    "\"" * replace(x, "\"" => "\"\"") * "\"" : String(x)
_csv_fmt(x::Nothing) = ""
_csv_fmt(x::Missing) = ""
_csv_fmt(x::Bool) = x ? "true" : "false"
_csv_fmt(x::Integer) = string(x)
function _csv_fmt(x::AbstractFloat)
    isfinite(x) || return ""
    return string(Float64(x))
end
_csv_fmt(x::Symbol) = _csv_escape(String(x))
_csv_fmt(x::AbstractString) = _csv_escape(x)

function _parse_opt_float(s::AbstractString)
    t = strip(s)
    (isempty(t) || lowercase(t) in ("na", "nan", "null", "none")) && return NaN
    return parse(Float64, t)
end

function _parse_opt_bool(s::AbstractString)
    t = lowercase(strip(s))
    t in ("true", "1", "t", "yes") && return true
    t in ("false", "0", "f", "no") && return false
    throw(ArgumentError("cannot parse boolean value $(repr(s))"))
end

function _wilson_hilferty_z(mnsq::Float64, q2::Float64; cap::Float64 = 9.9, whexact::Bool = true)
    !(isfinite(mnsq) && mnsq >= 0.0 && isfinite(q2) && q2 > 0.0) && return NaN
    q = sqrt(q2)
    z = 3.0 * (cbrt(mnsq) - 1.0) / q + (whexact ? q / 3.0 : 0.0)
    isfinite(z) || return NaN
    return clamp(z, -cap, cap)
end

function _sha256_hex_file(path::AbstractString)
    return open(io -> bytes2hex(_ROOT.SHA.sha256(io)), path, "r")
end

"""
    load_exchange_manifest(study_dir; scenarios = nothing, models = nothing, max_rep = nothing)

Read an `Exchange Schema v1.0` study manifest (`manifest.csv` and optional `protocol.json`)
from `study_dir` without modifying any files in `study_dir`.
"""
function load_exchange_manifest(
        study_dir::AbstractString;
        scenarios = nothing,
        models = nothing,
        max_rep::Union{Nothing,Integer} = nothing)
    sdir = abspath(study_dir)
    isdir(sdir) || throw(ArgumentError("study_dir does not exist: $sdir"))
    mpath = joinpath(sdir, "manifest.csv")
    csv = _read_simple_csv(mpath)
    col_idx = Dict(nm => i for (i, nm) in enumerate(csv.header))
    req = ("case_id", "rep", "scenario", "model", "n_persons", "n_raters",
           "n_criteria", "n_steps", "n_obs", "input_relpath", "input_sha256")
    for k in req
        haskey(col_idx, k) || throw(ArgumentError("manifest.csv missing required column $(repr(k))"))
    end
    scen_set = scenarios === nothing ? nothing : Set(String.(collect(scenarios)))
    mod_set = models === nothing ? nothing : Set(uppercase.(String.(collect(models))))

    entries = NamedTuple[]
    for r in csv.rows
        scen = strip(r[col_idx["scenario"]])
        mod = uppercase(strip(r[col_idx["model"]]))
        rep_i = parse(Int, strip(r[col_idx["rep"]]))
        scen_set !== nothing && !(scen in scen_set) && continue
        mod_set !== nothing && !(mod in mod_set) && continue
        max_rep !== nothing && rep_i > Int(max_rep) && continue

        relp = strip(r[col_idx["input_relpath"]])
        in_path = normpath(joinpath(sdir, relp))
        cdir = dirname(in_path)
        push!(entries, (;
            case_id = strip(r[col_idx["case_id"]]),
            rep = rep_i,
            seed = haskey(col_idx, "seed") ? parse(Int, strip(r[col_idx["seed"]])) : 0,
            track = haskey(col_idx, "track") ? strip(r[col_idx["track"]]) : "",
            scenario = scen,
            model = mod,
            n_persons = parse(Int, strip(r[col_idx["n_persons"]])),
            n_raters = parse(Int, strip(r[col_idx["n_raters"]])),
            n_criteria = parse(Int, strip(r[col_idx["n_criteria"]])),
            n_steps = parse(Int, strip(r[col_idx["n_steps"]])),
            raters_per_person = haskey(col_idx, "raters_per_person") ? parse(Int, strip(r[col_idx["raters_per_person"]])) : 0,
            n_obs = parse(Int, strip(r[col_idx["n_obs"]])),
            ability_sd = haskey(col_idx, "ability_sd") ? _parse_opt_float(r[col_idx["ability_sd"]]) : NaN,
            shared_sd = haskey(col_idx, "shared_sd") ? _parse_opt_float(r[col_idx["shared_sd"]]) : NaN,
            impact = haskey(col_idx, "impact") ? _parse_opt_float(r[col_idx["impact"]]) : 0.0,
            dff_effect = haskey(col_idx, "dff_effect") ? _parse_opt_float(r[col_idx["dff_effect"]]) : 0.0,
            has_bias_group = haskey(col_idx, "has_bias_group") ? _parse_opt_bool(r[col_idx["has_bias_group"]]) : false,
            has_validation_panel = haskey(col_idx, "has_validation_panel") ? _parse_opt_bool(r[col_idx["has_validation_panel"]]) : false,
            input_relpath = relp,
            input_path = in_path,
            case_dir = cdir,
            input_sha256 = lowercase(strip(r[col_idx["input_sha256"]])),
        ))
    end

    ppath = joinpath(sdir, "protocol.json")
    protocol = isfile(ppath) ? _ROOT.JSON3.read(read(ppath, String)) : nothing
    return (;
        schema_version = EXCHANGE_SCHEMA_VERSION,
        study_dir = sdir,
        protocol,
        n_cases = length(entries),
        cases = entries,
    )
end

"""
    load_exchange_case(case_dir_or_csv; manifest_row = nothing, truth_path = nothing, verify_sha256 = true)

Read a single `Exchange Schema v1.0` case (`input.csv`, optional `validation_input.csv`,
and optional `truth.json` from `truth/<case_id>/truth.json` or `truth_path`) in read-only mode.
"""
function load_exchange_case(
        case_dir_or_csv::AbstractString;
        manifest_row = nothing,
        truth_path::Union{Nothing,AbstractString} = nothing,
        verify_sha256::Bool = true)
    p_abs = abspath(case_dir_or_csv)
    input_csv = isdir(p_abs) ? joinpath(p_abs, "input.csv") : p_abs
    isfile(input_csv) || throw(ArgumentError("Exchange Schema input.csv does not exist: $input_csv"))
    cdir = dirname(input_csv)
    cid = manifest_row !== nothing && hasproperty(manifest_row, :case_id) ?
        String(manifest_row.case_id) : basename(cdir)

    actual_sha = _sha256_hex_file(input_csv)
    if verify_sha256 && manifest_row !== nothing && hasproperty(manifest_row, :input_sha256)
        exp_sha = lowercase(String(manifest_row.input_sha256))
        !isempty(exp_sha) && actual_sha != exp_sha && throw(ArgumentError(
            "Exchange Schema SHA-256 mismatch for $input_csv: expected $exp_sha, got $actual_sha"))
    end

    csv = _read_simple_csv(input_csv)
    cidx = Dict(nm => i for (i, nm) in enumerate(csv.header))
    for req_c in ("person", "rater", "criterion", "score")
        haskey(cidx, req_c) || throw(ArgumentError("input.csv missing required column $(repr(req_c))"))
    end
    has_group_col = haskey(cidx, "group")
    n = length(csv.rows)
    n > 0 || throw(ArgumentError("input.csv has zero observation rows: $input_csv"))

    person = Vector{Int}(undef, n)
    rater = Vector{Int}(undef, n)
    criterion = Vector{Int}(undef, n)
    score = Vector{Int}(undef, n)
    group = Vector{Int}(undef, n)

    person_group_map = Dict{Int,Int}()
    for (i, row) in enumerate(csv.rows)
        pi = parse(Int, strip(row[cidx["person"]]))
        ri = parse(Int, strip(row[cidx["rater"]]))
        ci = parse(Int, strip(row[cidx["criterion"]]))
        si = parse(Int, strip(row[cidx["score"]]))
        gi = has_group_col ? parse(Int, strip(row[cidx["group"]])) : 0
        person[i] = pi
        rater[i] = ri
        criterion[i] = ci
        score[i] = si
        group[i] = gi
        if haskey(person_group_map, pi)
            person_group_map[pi] == gi || throw(ArgumentError(
                "person $pi appears in multiple groups ($(person_group_map[pi]) vs $gi) in $input_csv"))
        else
            person_group_map[pi] = gi
        end
    end

    u_persons = sort!(collect(keys(person_group_map)))
    roster = (;
        person = u_persons,
        group = [person_group_map[p] for p in u_persons],
    )
    table = (; person, rater, criterion, score, group)

    n_steps = manifest_row !== nothing && hasproperty(manifest_row, :n_steps) ?
        Int(manifest_row.n_steps) : (maximum(score) - minimum(score))
    min_cat = minimum(score) <= 0 ? minimum(score) : 0
    category_levels = collect(min_cat:(min_cat + n_steps))

    # Locate optional truth.json (sibling `../../truth/<case_id>/truth.json` or `truth.json` in case_dir)
    resolved_truth_path = if truth_path !== nothing
        abspath(truth_path)
    else
        cand1 = joinpath(cdir, "truth.json")
        cand2 = normpath(joinpath(cdir, "..", "..", "truth", cid, "truth.json"))
        isfile(cand1) ? cand1 : (isfile(cand2) ? cand2 : nothing)
    end
    truth = (resolved_truth_path !== nothing && isfile(resolved_truth_path)) ?
        _ROOT.JSON3.read(read(resolved_truth_path, String)) : nothing

    val_csv_path = joinpath(cdir, "validation_input.csv")
    has_val = isfile(val_csv_path)

    return (;
        schema_version = EXCHANGE_SCHEMA_VERSION,
        case_id = cid,
        case_dir = cdir,
        input_path = input_csv,
        input_sha256 = actual_sha,
        n_obs = n,
        n_persons = length(u_persons),
        n_raters = length(unique(rater)),
        n_criteria = length(unique(criterion)),
        category_levels,
        model = manifest_row !== nothing && hasproperty(manifest_row, :model) ? String(manifest_row.model) : "RSM",
        table,
        roster,
        has_groups = length(unique(roster.group)) >= 2,
        has_validation_input = has_val,
        validation_input_path = has_val ? val_csv_path : nothing,
        truth_path = resolved_truth_path,
        truth,
        manifest_row,
    )
end

function _compute_mrcml_obs_fit_stats_and_fair_m(
        op,
        person_idx::Vector{Int},
        P::Int,
        facets_info,
        group::Vector{Int},
        supports::Vector{UnitRange{Int}},
        categories::Vector{Int},
        category::Vector{Int},
        theta_est::Vector{Float64},
        eta_free::Vector{Float64},
        xi_model::Vector{Float64};
        weights::AbstractVector{<:Real} = ones(Float64, op.n_obs),
        zstd_cap::Float64 = 9.9,
        whexact::Bool = true)
    n_obs = op.n_obs
    v_pat = copy(op.c_pat)
    _ROOT.LinearAlgebra.mul!(v_pat, op.A_free, eta_free, 1.0, 1.0)

    p_wsum = zeros(Float64, P)
    p_wcnt = zeros(Float64, P)
    p_e2 = zeros(Float64, P)
    p_z2 = zeros(Float64, P)
    p_q2_in = zeros(Float64, P)
    p_q2_out = zeros(Float64, P)
    p_bproxy = falses(P)
    p_unavail = zeros(Int, P)

    f_maps = Dict{Symbol,NamedTuple}()
    for fb in facets_info
        L = length(fb.levels)
        f_maps[fb.name] = (;
            levels = fb.levels,
            index = fb.index,
            wsum = zeros(Float64, L),
            wcnt = zeros(Float64, L),
            e2 = zeros(Float64, L),
            z2 = zeros(Float64, L),
            q2_in = zeros(Float64, L),
            q2_out = zeros(Float64, L),
            bproxy = falses(L),
            unavail = zeros(Int, L),
        )
    end

    K_max = maximum(length, supports)
    lbuf = zeros(Float64, K_max)
    pbuf = zeros(Float64, K_max)

    @inbounds for n in 1:n_obs
        p = person_idx[n]
        wn = Float64(weights[n])
        th = theta_est[p]
        if !isfinite(th)
            p_wcnt[p] += wn
            p_bproxy[p] = true
            for (_, acc) in f_maps
                j = acc.index[n]
                acc.wcnt[j] += wn
                acc.bproxy[j] = true
            end
            continue
        end
        prng = op.pattern_ranges[op.pattern_of_row[n]]
        sup = supports[group[n]]
        M_g = length(sup)
        mmax = -Inf
        for lk in 1:M_g
            m = prng[lk]
            v = op.B_pat[m] * th + v_pat[m]
            lbuf[lk] = v
            v > mmax && (mmax = v)
        end
        ssum = 0.0
        for lk in 1:M_g
            e = exp(lbuf[lk] - mmax)
            pbuf[lk] = e
            ssum += e
        end
        inv_s = 1.0 / ssum
        eb = 0.0
        for lk in 1:M_g
            pk = pbuf[lk] * inv_s
            pbuf[lk] = pk
            eb += pk * op.B_pat[prng[lk]]
        end
        w_var = 0.0
        kurt = 0.0
        for lk in 1:M_g
            d = op.B_pat[prng[lk]] - eb
            d2 = d * d
            w_var += pbuf[lk] * d2
            kurt += pbuf[lk] * d2 * d2
        end
        p_wcnt[p] += wn
        for (_, acc) in f_maps
            acc.wcnt[acc.index[n]] += wn
        end
        if !(isfinite(w_var) && w_var > 1e-10)
            p_unavail[p] += 1
            for (_, acc) in f_maps
                acc.unavail[acc.index[n]] += 1
            end
            continue
        end
        yk_loc = category[n] - first(sup) + 1
        b_obs = op.B_pat[prng[yk_loc]]
        e2 = (b_obs - eb)^2
        z2 = e2 / w_var
        var_e2 = max(kurt - w_var * w_var, 0.0)
        var_z2 = var_e2 / (w_var * w_var)

        p_wsum[p] += wn * w_var
        p_e2[p] += wn * e2
        p_z2[p] += wn * z2
        p_q2_in[p] += wn * var_e2
        p_q2_out[p] += wn * var_z2

        for (_, acc) in f_maps
            j = acc.index[n]
            acc.wsum[j] += wn * w_var
            acc.e2[j] += wn * e2
            acc.z2[j] += wn * z2
            acc.q2_in[j] += wn * var_e2
            acc.q2_out[j] += wn * var_z2
        end
    end

    person_fit = map(1:P) do p
        if isfinite(theta_est[p]) && p_unavail[p] == 0 && p_wcnt[p] > 0.0 && p_wsum[p] > 1e-10
            in_m = p_e2[p] / p_wsum[p]
            out_m = p_z2[p] / p_wcnt[p]
            q2_i = p_q2_in[p] / (p_wsum[p]^2)
            q2_o = p_q2_out[p] / (p_wcnt[p]^2)
            (; infit_mnsq = in_m,
               infit_z = p_bproxy[p] ? NaN : _wilson_hilferty_z(in_m, q2_i; cap = zstd_cap, whexact),
               outfit_mnsq = out_m,
               outfit_z = p_bproxy[p] ? NaN : _wilson_hilferty_z(out_m, q2_o; cap = zstd_cap, whexact))
        else
            (; infit_mnsq = NaN, infit_z = NaN, outfit_mnsq = NaN, outfit_z = NaN)
        end
    end

    facet_fit = Dict{Symbol,Vector{NamedTuple}}()
    for (fname, acc) in f_maps
        L = length(acc.levels)
        facet_fit[fname] = map(1:L) do j
            if acc.unavail[j] == 0 && acc.wcnt[j] > 0.0 && acc.wsum[j] > 1e-10
                in_m = acc.e2[j] / acc.wsum[j]
                out_m = acc.z2[j] / acc.wcnt[j]
                q2_i = acc.q2_in[j] / (acc.wsum[j]^2)
                q2_o = acc.q2_out[j] / (acc.wcnt[j]^2)
                (; infit_mnsq = in_m,
                   infit_z = acc.bproxy[j] ? NaN : _wilson_hilferty_z(in_m, q2_i; cap = zstd_cap, whexact),
                   outfit_mnsq = out_m,
                   outfit_z = acc.bproxy[j] ? NaN : _wilson_hilferty_z(out_m, q2_o; cap = zstd_cap, whexact))
            else
                (; infit_mnsq = NaN, infit_z = NaN, outfit_mnsq = NaN, outfit_z = NaN)
            end
        end
    end

    # Canonical FACETS Fair(M) on category scale: average expected score across step groups
    # at rater_mean = 0, criterion_mean = 0.
    step_bms = [bm for bm in op.block_meta if bm.kind === :steps]
    fair_m = fill(NaN, P)
    if !isempty(step_bms) && length(step_bms) == length(supports) && allequal(supports)
        sup1 = supports[1]
        cat_vals = Float64[categories[k] for k in sup1]
        G_s = length(step_bms)
        step_vecs = [xi_model[step_bms[g].model_range] for g in 1:G_s]
        for p in 1:P
            th = theta_est[p]
            isfinite(th) || continue
            acc_e = 0.0
            for g in 1:G_s
                acc_e += _ROOT.AdditiveFacets._adjacent_expected_score(th, step_vecs[g], cat_vals)
            end
            fair_m[p] = acc_e / G_s
        end
    end

    return (; person_fit, facet_fit, fair_m)
end

function _compute_native_obs_fit_stats(
        prob,
        lay,
        full_params::Vector{Float64},
        theta_est::Vector{Float64};
        zstd_cap::Float64 = 9.9,
        whexact::Bool = true)
    n_obs = prob.n_obs
    P = length(prob.person_levels)
    p_wsum = zeros(Float64, P)
    p_wcnt = zeros(Float64, P)
    p_e2 = zeros(Float64, P)
    p_z2 = zeros(Float64, P)
    p_q2_in = zeros(Float64, P)
    p_q2_out = zeros(Float64, P)
    p_bproxy = falses(P)
    p_unavail = zeros(Int, P)

    f_maps = Dict{Symbol,NamedTuple}()
    for fd in prob.facets
        L = length(fd.levels)
        f_maps[fd.name] = (;
            levels = fd.levels,
            index = fd.index,
            wsum = zeros(Float64, L),
            wcnt = zeros(Float64, L),
            e2 = zeros(Float64, L),
            z2 = zeros(Float64, L),
            q2_in = zeros(Float64, L),
            q2_out = zeros(Float64, L),
            bproxy = falses(L),
            unavail = zeros(Int, L),
        )
    end

    K_max = maximum(length, prob.supports)
    pbuf = zeros(Float64, K_max)

    @inbounds for r in 1:n_obs
        p = prob.person_idx[r]
        wn = Float64(prob.weights[r])
        th = theta_est[p]
        if !isfinite(th)
            p_wcnt[p] += wn
            p_bproxy[p] = true
            for (_, acc) in f_maps
                j = acc.index[r]
                acc.wcnt[j] += wn
                acc.bproxy[j] = true
            end
            continue
        end
        eta = th
        for (fi, fd) in enumerate(prob.facets)
            eta += fd.sign * full_params[lay.facet_full_ranges[fi][fd.index[r]]]
        end
        g = prob.step_group[r]
        K_g = length(prob.supports[g])
        srng = lay.step_full_ranges[g]
        pv = view(pbuf, 1:K_g)
        _ROOT.FrequentistMFRM._row_probs!(pv, eta, view(full_params, srng))
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
        p_wcnt[p] += wn
        for (_, acc) in f_maps
            acc.wcnt[acc.index[r]] += wn
        end
        if !(isfinite(vk) && vk > 1e-10)
            p_unavail[p] += 1
            for (_, acc) in f_maps
                acc.unavail[acc.index[r]] += 1
            end
            continue
        end
        yk = prob.score_k[r]
        e2 = (yk - ek)^2
        z2 = e2 / vk
        var_e2 = max(m4k - vk * vk, 0.0)
        var_z2 = var_e2 / (vk * vk)

        p_wsum[p] += wn * vk
        p_e2[p] += wn * e2
        p_z2[p] += wn * z2
        p_q2_in[p] += wn * var_e2
        p_q2_out[p] += wn * var_z2

        for (_, acc) in f_maps
            j = acc.index[r]
            acc.wsum[j] += wn * vk
            acc.e2[j] += wn * e2
            acc.z2[j] += wn * z2
            acc.q2_in[j] += wn * var_e2
            acc.q2_out[j] += wn * var_z2
        end
    end

    person_fit = map(1:P) do p
        if isfinite(theta_est[p]) && p_unavail[p] == 0 && p_wcnt[p] > 0.0 && p_wsum[p] > 1e-10
            in_m = p_e2[p] / p_wsum[p]
            out_m = p_z2[p] / p_wcnt[p]
            q2_i = p_q2_in[p] / (p_wsum[p]^2)
            q2_o = p_q2_out[p] / (p_wcnt[p]^2)
            (; infit_mnsq = in_m,
               infit_z = p_bproxy[p] ? NaN : _wilson_hilferty_z(in_m, q2_i; cap = zstd_cap, whexact),
               outfit_mnsq = out_m,
               outfit_z = p_bproxy[p] ? NaN : _wilson_hilferty_z(out_m, q2_o; cap = zstd_cap, whexact))
        else
            (; infit_mnsq = NaN, infit_z = NaN, outfit_mnsq = NaN, outfit_z = NaN)
        end
    end

    facet_fit = Dict{Symbol,Vector{NamedTuple}}()
    for (fname, acc) in f_maps
        L = length(acc.levels)
        facet_fit[fname] = map(1:L) do j
            if acc.unavail[j] == 0 && acc.wcnt[j] > 0.0 && acc.wsum[j] > 1e-10
                in_m = acc.e2[j] / acc.wsum[j]
                out_m = acc.z2[j] / acc.wcnt[j]
                q2_i = acc.q2_in[j] / (acc.wsum[j]^2)
                q2_o = acc.q2_out[j] / (acc.wcnt[j]^2)
                (; infit_mnsq = in_m,
                   infit_z = acc.bproxy[j] ? NaN : _wilson_hilferty_z(in_m, q2_i; cap = zstd_cap, whexact),
                   outfit_mnsq = out_m,
                   outfit_z = acc.bproxy[j] ? NaN : _wilson_hilferty_z(out_m, q2_o; cap = zstd_cap, whexact))
            else
                (; infit_mnsq = NaN, infit_z = NaN, outfit_mnsq = NaN, outfit_z = NaN)
            end
        end
    end
    return (; person_fit, facet_fit)
end

function _extreme_flag_int(ext::Symbol)
    ext === :all_minimum && return -1
    ext === :all_maximum && return 1
    return 0
end

"""
    write_exchange_run(out_dir, fit; case_id, input_sha256, estimator, engine = "BayesianMGMFRM.jl",
                       model = "RSM", person_score_method = :auto, contrast_rows = nothing,
                       elapsed_sec = nothing, extra = Dict{String,Any}(), overwrite = false)

Emit `Exchange Schema v1.0` output artifacts (`meta.json`, `facets.csv`, `steps.csv`,
`person.csv`, and optional `contrast.csv`) into `out_dir` for either a frequentist
`FrequentistMFRM.Fit` (`:mmle` or `:jmle`) or a Bayesian `AdditiveFacets.Fit` (`MRCMLTarget`).
"""
function _compute_bayesian_mnsq_means(
        t,
        op,
        th_draws_raw::Matrix{Float64},
        eta_draws::Matrix{Float64})
    S_draws, P = size(th_draws_raw)
    n_obs = op.n_obs
    F = length(t.facets)
    M_max = maximum(length, t.supports)

    obs_b = Vector{Float64}(undef, n_obs)
    @inbounds for n in 1:n_obs
        prng = op.pattern_ranges[op.pattern_of_row[n]]
        sup = t.supports[t.group[n]]
        obs_b[n] = op.B_pat[prng[t.category[n] - first(sup) + 1]]
    end

    vp = Vector{Float64}(undef, length(op.c_pat))
    lbuf = Vector{Float64}(undef, M_max)
    pbuf = Vector{Float64}(undef, M_max)

    p_w = Vector{Float64}(undef, P)
    p_cnt = Vector{Int}(undef, P)
    p_e2 = Vector{Float64}(undef, P)
    p_z2 = Vector{Float64}(undef, P)
    p_in_sum = zeros(Float64, P)
    p_out_sum = zeros(Float64, P)
    p_ok = trues(P)

    f_L = Int[length(fb.levels) for fb in t.facets]
    f_idx = Vector{Int}[fb.index for fb in t.facets]
    f_w = [Vector{Float64}(undef, L) for L in f_L]
    f_cnt = [Vector{Int}(undef, L) for L in f_L]
    f_e2 = [Vector{Float64}(undef, L) for L in f_L]
    f_z2 = [Vector{Float64}(undef, L) for L in f_L]
    f_in_sum = [zeros(Float64, L) for L in f_L]
    f_out_sum = [zeros(Float64, L) for L in f_L]
    f_ok = [trues(L) for L in f_L]

    d_xi = size(op.A_free, 2)
    rows_A = SparseArrays.rowvals(op.A_free)
    vals_A = SparseArrays.nonzeros(op.A_free)

    @inbounds for s_idx in 1:S_draws
        copyto!(vp, op.c_pat)
        for col in 1:d_xi
            ec = eta_draws[s_idx, col]
            ec == 0.0 && continue
            for ptr in SparseArrays.nzrange(op.A_free, col)
                vp[rows_A[ptr]] += vals_A[ptr] * ec
            end
        end

        fill!(p_w, 0.0); fill!(p_cnt, 0); fill!(p_e2, 0.0); fill!(p_z2, 0.0)
        for fk in 1:F
            fill!(f_w[fk], 0.0); fill!(f_cnt[fk], 0); fill!(f_e2[fk], 0.0); fill!(f_z2[fk], 0.0)
        end

        for n in 1:n_obs
            prng = op.pattern_ranges[op.pattern_of_row[n]]
            M_g = length(prng)
            p = t.person[n]
            th = th_draws_raw[s_idx, p]
            mmax = -Inf
            for lk in 1:M_g
                m = prng[lk]
                v = op.B_pat[m] * th + vp[m]
                lbuf[lk] = v
                v > mmax && (mmax = v)
            end
            ssum = 0.0
            for lk in 1:M_g
                e = exp(lbuf[lk] - mmax)
                pbuf[lk] = e
                ssum += e
            end
            inv_s = 1.0 / ssum
            eb = 0.0
            for lk in 1:M_g
                pk = pbuf[lk] * inv_s
                pbuf[lk] = pk
                eb += pk * op.B_pat[prng[lk]]
            end
            wn = 0.0
            for lk in 1:M_g
                db = op.B_pat[prng[lk]] - eb
                wn += pbuf[lk] * db * db
            end
            if wn > 1e-14
                d_obs = obs_b[n] - eb
                e2_o = d_obs * d_obs
                z2_o = e2_o / wn
                p_w[p] += wn
                p_cnt[p] += 1
                p_e2[p] += e2_o
                p_z2[p] += z2_o
                for fk in 1:F
                    j = f_idx[fk][n]
                    f_w[fk][j] += wn
                    f_cnt[fk][j] += 1
                    f_e2[fk][j] += e2_o
                    f_z2[fk][j] += z2_o
                end
            end
        end

        for p in 1:P
            if p_cnt[p] > 0 && p_w[p] > 0.0
                p_in_sum[p] += p_e2[p] / p_w[p]
                p_out_sum[p] += p_z2[p] / p_cnt[p]
            else
                p_ok[p] = false
            end
        end
        for fk in 1:F
            w_v = f_w[fk]; c_v = f_cnt[fk]; e2_v = f_e2[fk]; z2_v = f_z2[fk]
            in_s = f_in_sum[fk]; out_s = f_out_sum[fk]; ok_v = f_ok[fk]
            for j in 1:f_L[fk]
                if c_v[j] > 0 && w_v[j] > 0.0
                    in_s[j] += e2_v[j] / w_v[j]
                    out_s[j] += z2_v[j] / c_v[j]
                else
                    ok_v[j] = false
                end
            end
        end
    end

    inv_S = 1.0 / S_draws
    p_in = Float64[p_ok[p] ? p_in_sum[p] * inv_S : NaN for p in 1:P]
    p_out = Float64[p_ok[p] ? p_out_sum[p] * inv_S : NaN for p in 1:P]
    f_map = Dict{Symbol,Tuple{Vector{Float64},Vector{Float64}}}()
    for (fk, fb) in enumerate(t.facets)
        in_v = Float64[f_ok[fk][j] ? f_in_sum[fk][j] * inv_S : NaN for j in 1:f_L[fk]]
        out_v = Float64[f_ok[fk][j] ? f_out_sum[fk][j] * inv_S : NaN for j in 1:f_L[fk]]
        f_map[fb.name] = (in_v, out_v)
    end
    return (; p_in, p_out, f_map)
end

function write_exchange_run(
        out_dir::AbstractString,
        fit;
        case_id::AbstractString,
        input_sha256::AbstractString,
        estimator::AbstractString,
        engine::AbstractString = "BayesianMGMFRM.jl",
        model::AbstractString = "RSM",
        spec = nothing,
        qualification = nothing,
        person_score_method::Symbol = :auto,
        zstd_cap::Real = 9.9,
        zstd_whexact::Bool = true,
        contrast_rows = nothing,
        elapsed_sec::Union{Nothing,Real} = nothing,
        extra::AbstractDict = Dict{String,Any}(),
        overwrite::Bool = false)
    mod_upper = uppercase(String(model))
    mod_upper in ("RSM", "PCM") || throw(ArgumentError("model must be \"RSM\" or \"PCM\"; got $(repr(model))"))
    zstd_cap isa Real && !(zstd_cap isa Bool) && isfinite(zstd_cap) && Float64(zstd_cap) > 0.0 ||
        throw(ArgumentError("zstd_cap must be a finite positive real number; got $(repr(zstd_cap))"))
    zcap_f = Float64(zstd_cap)
    zwhex = Bool(zstd_whexact)

    extra_dict = Dict{String,Any}(String(k) => v for (k, v) in pairs(extra))
    if haskey(extra_dict, "model_type") && uppercase(String(string(extra_dict["model_type"]))) != mod_upper
        throw(ArgumentError("extra[\"model_type\"] ($(repr(extra_dict["model_type"]))) conflicts with model = $(repr(mod_upper))"))
    end
    if fit isa _ROOT.FrequentistMFRM.Fit
        if haskey(extra_dict, "zstd_cap")
            v_cap = extra_dict["zstd_cap"]
            (v_cap isa Real && !(v_cap isa Bool) && Float64(v_cap) == zcap_f) ||
                throw(ArgumentError("extra[\"zstd_cap\"] ($(repr(v_cap))) conflicts with applied zstd_cap = $zcap_f; pass `zstd_cap = ...` directly to `write_exchange_run`"))
        end
        if haskey(extra_dict, "zstd_whexact")
            v_wh = extra_dict["zstd_whexact"]
            (v_wh isa Bool && v_wh == zwhex) ||
                throw(ArgumentError("extra[\"zstd_whexact\"] ($(repr(v_wh))) conflicts with applied zstd_whexact = $zwhex; pass `zstd_whexact = ...` directly to `write_exchange_run`"))
        end
        s_chk = _ROOT.FrequentistMFRM.checked(fit).summary
        def_sm = s_chk.method === :mmle ? :eap : :jml
        sm_chk = person_score_method === :auto ? def_sm : person_score_method
        sm_chk in (:eap, :wle, :jml, :mle) ||
            throw(ArgumentError("person_score_method must be :auto, :eap, :wle, :jml, or :mle; got $(repr(person_score_method))"))
        if s_chk.method === :mmle && !(sm_chk in (:eap, :wle, :mle))
            throw(ArgumentError("person_score_method = $(repr(sm_chk)) is incompatible with method = :mmle; choose :auto, :eap, :wle, or :mle"))
        elseif s_chk.method === :jmle && !(sm_chk in (:jml, :wle))
            throw(ArgumentError("person_score_method = $(repr(sm_chk)) is incompatible with method = :jmle; choose :auto, :jml, or :wle"))
        end
    elseif fit isa _ROOT.AdditiveFacets.Fit
        person_score_method in (:auto, :nuts_mean) ||
            throw(ArgumentError("Bayesian `write_exchange_run` supports only person_score_method = :auto or :nuts_mean; got $(repr(person_score_method))"))
        if haskey(extra_dict, "zstd_cap") && extra_dict["zstd_cap"] !== nothing
            throw(ArgumentError("extra[\"zstd_cap\"] is not applicable to Bayesian fits (frequentist ZSTD is not emitted)"))
        end
        if haskey(extra_dict, "zstd_whexact") && extra_dict["zstd_whexact"] !== nothing
            throw(ArgumentError("extra[\"zstd_whexact\"] is not applicable to Bayesian fits (frequentist ZSTD is not emitted)"))
        end
    else
        throw(ArgumentError("unsupported fit type $(typeof(fit)) for write_exchange_run"))
    end

    odir = abspath(out_dir)
    if isdir(odir) && !isempty(readdir(odir)) && !overwrite
        throw(ArgumentError("Exchange run output directory already exists and is non-empty: $odir (pass overwrite = true to replace)"))
    end
    mkpath(odir)

    facets_out = NamedTuple[]
    steps_out = NamedTuple[]
    person_out = NamedTuple[]
    warnings_out = String[]
    converged_flag = false
    status_str = "ok"
    n_obs_used = 0
    el_sec = elapsed_sec === nothing ? 0.0 : Float64(elapsed_sec)

    if fit isa _ROOT.FrequentistMFRM.Fit
        r = _ROOT.FrequentistMFRM.checked(fit)
        s = r.summary
        prob = r.problem
        converged_flag = Bool(s.converged)
        status_str = converged_flag ? "ok" : "nonconverged"
        n_obs_used = Int(s.n_observations)
        elapsed_sec === nothing && (el_sec = Float64(s.elapsed_seconds))
        append!(warnings_out, r.warnings)

        default_score_m = s.method === :mmle ? :eap : :jml
        score_m = person_score_method === :auto ? default_score_m : person_score_method
        score_label = uppercase(String(score_m))
        use_stored_fit = score_m === default_score_m
        fit_whex = Bool(get(r.overall_fit, :whexact, true))

        _f64_na(x) = x === missing ? NaN : Float64(x)
        _stored_fit_tuple(row) = begin
            in_m = _f64_na(get(row, :infit, missing))
            out_m = _f64_na(get(row, :outfit, missing))
            df_i = _f64_na(get(row, :df_infit, missing))
            df_o = _f64_na(get(row, :df_outfit, missing))
            iz_raw = get(row, :infit_zstd, missing)
            oz_raw = get(row, :outfit_zstd, missing)
            in_z = (iz_raw === missing) ? NaN :
                ((isfinite(in_m) && isfinite(df_i) && df_i > 0.0) ?
                    _wilson_hilferty_z(in_m, 2.0 / df_i; cap = zcap_f, whexact = zwhex) :
                    (zwhex == fit_whex && isfinite(_f64_na(iz_raw)) ? clamp(_f64_na(iz_raw), -zcap_f, zcap_f) : NaN))
            out_z = (oz_raw === missing) ? NaN :
                ((isfinite(out_m) && isfinite(df_o) && df_o > 0.0) ?
                    _wilson_hilferty_z(out_m, 2.0 / df_o; cap = zcap_f, whexact = zwhex) :
                    (zwhex == fit_whex && isfinite(_f64_na(oz_raw)) ? clamp(_f64_na(oz_raw), -zcap_f, zcap_f) : NaN))
            (; infit_mnsq = in_m, infit_z = in_z, outfit_mnsq = out_m, outfit_z = out_z)
        end

        if hasproperty(r, :mrcml_operator)
            op = r.mrcml_operator
            P = length(prob.person_levels)
            th_vec = [
                score_m === :wle ? _f64_na(ps.wle) :
                score_m === :mle ? _f64_na(ps.mle) :
                _f64_na(ps.estimate)
                for ps in r.person_scores
            ]
            se_vec = [
                score_m === :wle ? _f64_na(ps.wle_se) :
                score_m === :mle ? _f64_na(ps.mle_se) :
                _f64_na(ps.se)
                for ps in r.person_scores
            ]
            cats = sort!(unique(reduce(vcat, r.mrcml_category_labels)))
            cat_idx_map = Dict(v => i for (i, v) in enumerate(cats))
            cat_1based = [cat_idx_map[v] for v in prob.raw_score]
            sups_1based = [cat_idx_map[first(lbls)]:cat_idx_map[last(lbls)] for lbls in r.mrcml_category_labels]
            xi_mod = op.xi0_model .+ Vector{Float64}(op.J_model * r.eta_free)

            diag_aux = _compute_mrcml_obs_fit_stats_and_fair_m(
                op, prob.person_idx, P, prob.facets, prob.step_group, sups_1based, cats, cat_1based,
                th_vec, r.eta_free, xi_mod;
                weights = prob.weights, zstd_cap = zcap_f, whexact = zwhex,
            )
            stored_by_param = Dict{String,NamedTuple}(
                String(fm.parameter) => fm for fm in r.facet_measures if haskey(fm, :parameter)
            )

            ext_dir = Dict((x.facet, x.level) => (x.direction === :all_minimum ? -1 : 1) for x in r.extreme_facet_levels)
            for bm in op.block_meta
                bm.kind in (:facet_main, :facet_lltm_strict, :facet_lltm_plus_residual) || continue
                fname = bm.name
                ff = get(diag_aux.facet_fit, fname, nothing)
                for (j, lvl) in enumerate(bm.levels)
                    m_idx = bm.model_range[j]
                    nm = op.model_names[m_idx]
                    est_v = xi_mod[m_idx]
                    se_v = r.full_se[r.covariance.offset + m_idx]
                    f_row = if use_stored_fit && haskey(stored_by_param, nm)
                        _stored_fit_tuple(stored_by_param[nm])
                    elseif ff !== nothing
                        ff[j]
                    else
                        (; infit_mnsq = NaN, infit_z = NaN, outfit_mnsq = NaN, outfit_z = NaN)
                    end
                    eflag = get(ext_dir, (fname, lvl), 0)
                    push!(facets_out, (;
                        facet = String(fname),
                        element = lvl,
                        measure = est_v,
                        se = se_v,
                        infit_mnsq = f_row.infit_mnsq,
                        infit_z = f_row.infit_z,
                        outfit_mnsq = f_row.outfit_mnsq,
                        outfit_z = f_row.outfit_z,
                        extreme_flag = eflag,
                    ))
                end
            end

            step_bms = [bm for bm in op.block_meta if bm.kind === :steps]
            for (g, bm) in enumerate(step_bms)
                crit_lbl = mod_upper == "RSM" ? "ALL" : string(bm.group_level)
                for (h, m_idx) in enumerate(bm.model_range)
                    push!(steps_out, (;
                        criterion = crit_lbl,
                        step = h,
                        measure = xi_mod[m_idx],
                        se = r.full_se[r.covariance.offset + m_idx],
                    ))
                end
            end

            for p in 1:P
                ps = r.person_scores[p]
                pf = use_stored_fit ? _stored_fit_tuple(ps) : diag_aux.person_fit[p]
                se_p = se_vec[p]
                rse_p = use_stored_fit ? _f64_na(get(ps, :real_se, missing)) :
                    ((isfinite(se_p) && isfinite(pf.infit_mnsq)) ? se_p * max(1.0, sqrt(max(pf.infit_mnsq, 0.0))) : NaN)
                push!(person_out, (;
                    person = ps.person,
                    measure = th_vec[p],
                    se = se_p,
                    real_se = rse_p,
                    fair_m = diag_aux.fair_m[p],
                    infit_mnsq = pf.infit_mnsq,
                    infit_z = pf.infit_z,
                    outfit_mnsq = pf.outfit_mnsq,
                    outfit_z = pf.outfit_z,
                    extreme_flag = _extreme_flag_int(ps.extreme),
                    score_method = score_label,
                ))
            end
        else
            # Native `FrequentistMFRM.Spec` fit
            P = length(prob.person_levels)
            th_vec = [
                score_m === :eap ? _f64_na(ps.estimate) :
                score_m === :wle ? _f64_na(ps.wle) :
                score_m === :mle ? _f64_na(ps.mle) :
                _f64_na(get(ps, :limit_estimate, ps.estimate))
                for ps in r.person_scores
            ]
            se_vec = [
                score_m === :wle ? _f64_na(ps.wle_se) :
                score_m === :mle ? _f64_na(ps.mle_se) :
                _f64_na(ps.se)
                for ps in r.person_scores
            ]
            alt_fit = use_stored_fit ? nothing :
                _compute_native_obs_fit_stats(prob, r.layout, r.full_parameters, th_vec; zstd_cap = zcap_f, whexact = zwhex)
            f_pos = Dict{Symbol,Int}()
            for fm in r.facet_measures
                eflag = 0
                for ex in r.extreme_facet_levels
                    if ex.facet === fm.facet && isequal(ex.level, fm.level)
                        eflag = ex.direction === :all_minimum ? -1 : 1
                    end
                end
                idx_l = get(f_pos, fm.facet, 0) + 1
                f_pos[fm.facet] = idx_l
                # In FrequentistMFRM, non-person facets use sign = -1 (+measure = stricter/harder); flip if sign == +1.
                est_f = _f64_na(fm.estimate)
                meas_f = fm.sign < 0 ? est_f : -est_f
                f_row = use_stored_fit ? _stored_fit_tuple(fm) : alt_fit.facet_fit[fm.facet][idx_l]
                push!(facets_out, (;
                    facet = String(fm.facet),
                    element = fm.level,
                    measure = meas_f,
                    se = _f64_na(fm.se),
                    infit_mnsq = f_row.infit_mnsq,
                    infit_z = f_row.infit_z,
                    outfit_mnsq = f_row.outfit_mnsq,
                    outfit_z = f_row.outfit_z,
                    extreme_flag = eflag,
                ))
            end
            for sm in r.step_measures
                crit_lbl = mod_upper == "RSM" ? "ALL" : string(sm.group)
                push!(steps_out, (;
                    criterion = crit_lbl,
                    step = Int(sm.step),
                    measure = _f64_na(sm.estimate),
                    se = _f64_na(sm.se),
                ))
            end
            # Compute canonical Fair(M) across step groups
            G_s = length(r.layout.step_full_ranges)
            sup1 = prob.supports[1]
            cat_vals = Float64.(collect(sup1))
            step_vecs = [r.full_parameters[srng] for srng in r.layout.step_full_ranges]
            for (p, ps) in enumerate(r.person_scores)
                th = score_m === :wle ? _f64_na(ps.wle) :
                     score_m === :mle ? _f64_na(ps.mle) :
                     _f64_na(ps.estimate)
                se_p = se_vec[p]
                pf = use_stored_fit ? _stored_fit_tuple(ps) : alt_fit.person_fit[p]
                rse_p = use_stored_fit ? _f64_na(get(ps, :real_se, missing)) :
                    ((isfinite(se_p) && isfinite(pf.infit_mnsq)) ? se_p * max(1.0, sqrt(max(pf.infit_mnsq, 0.0))) : NaN)
                fm_val = if isfinite(th) && allequal(prob.supports)
                    _ROOT.Statistics.mean(_ROOT.AdditiveFacets._adjacent_expected_score(th, step_vecs[g], cat_vals) for g in 1:G_s)
                else
                    NaN
                end
                push!(person_out, (;
                    person = ps.person,
                    measure = th,
                    se = se_p,
                    real_se = rse_p,
                    fair_m = fm_val,
                    infit_mnsq = pf.infit_mnsq,
                    infit_z = pf.infit_z,
                    outfit_mnsq = pf.outfit_mnsq,
                    outfit_z = pf.outfit_z,
                    extreme_flag = _extreme_flag_int(ps.extreme),
                    score_method = score_label,
                ))
            end
        end
    elseif fit isa _ROOT.AdditiveFacets.Fit
        t = spec === nothing ? _ROOT.AdditiveFacets.checked(fit; full = true) : spec
        t isa _ROOT.MRCML.Target || throw(ArgumentError("Exchange Schema Bayesian export requires an MRCMLTarget fit"))
        q_gate = qualification === nothing ? _ROOT.qualify(fit) : qualification
        converged_flag = Bool(q_gate.qualified)
        status_str = converged_flag ? "ok" : "nonconverged"
        n_obs_used = length(t.person)

        op = t.operator
        draws = fit.record.run.draws
        S_draws = size(draws, 1)
        P = length(t.people)
        n_mod = length(op.model_names)

        th_draws = Matrix{Float64}(undef, S_draws, P)
        xi_draws = Matrix{Float64}(undef, S_draws, n_mod)
        eta_draws = Matrix{Float64}(undef, S_draws, size(op.A_free, 2))
        for s_idx in 1:S_draws
            u = _ROOT.AdditiveFacets._mrcml_unpack(t, view(draws, s_idx, :))
            th_draws[s_idx, :] .= u.person
            xi_draws[s_idx, :] .= u.xi_model
            eta_draws[s_idx, :] .= u.eta_xi
        end

        # Fast single-pass posterior-integrated Infit/Outfit MNSQ before shifting `th_draws` by `population_mean`
        mnsq_post = _compute_bayesian_mnsq_means(t, op, th_draws, eta_draws)

        # Shift person abilities by global `population_mean` if present so person measures are on the absolute zero-sum facet scale!
        pop_mean_bm = findfirst(bm -> bm.kind === :population_mean, op.block_meta)
        if pop_mean_bm !== nothing
            pm_col = first(op.block_meta[pop_mean_bm].model_range)
            for s_idx in 1:S_draws
                th_draws[s_idx, :] .+= xi_draws[s_idx, pm_col]
            end
        end

        th_mean = vec(_ROOT.Statistics.mean(th_draws; dims = 1))
        th_sd = vec(_ROOT.Statistics.std(th_draws; dims = 1))
        xi_mean = vec(_ROOT.Statistics.mean(xi_draws; dims = 1))
        xi_sd = vec(_ROOT.Statistics.std(xi_draws; dims = 1))

        # Posterior-integrated Fair(M) across draws (averaging expected score across criteria per draw, then posterior mean!)
        step_bms = [bm for bm in op.block_meta if bm.kind === :steps]
        fair_m_post = fill(NaN, P)
        if !isempty(step_bms) && length(step_bms) == length(t.supports) && allequal(t.supports)
            sup1 = t.supports[1]
            cat_vals = Float64[t.categories[k] for k in sup1]
            G_s = length(step_bms)
            for p in 1:P
                acc_s = 0.0
                @inbounds for s_idx in 1:S_draws
                    th_ps = th_draws[s_idx, p]
                    acc_g = 0.0
                    for g in 1:G_s
                        acc_g += _ROOT.AdditiveFacets._adjacent_expected_score(
                            th_ps, view(xi_draws, s_idx, step_bms[g].model_range), cat_vals)
                    end
                    acc_s += acc_g / G_s
                end
                fair_m_post[p] = acc_s / S_draws
            end
        end

        p_ext = _ROOT.FrequentistMFRM._mrcml_person_extremes(
            op, op.n_obs, P, t.person, t.group, t.supports, t.category)
        f_ext_list = _ROOT.FrequentistMFRM._mrcml_extreme_facet_levels(t)
        f_ext_dir = Dict((x.facet, x.level) => (x.direction === :all_minimum ? -1 : 1) for x in f_ext_list)

        for bm in op.block_meta
            bm.kind in (:facet_main, :facet_lltm_strict, :facet_lltm_plus_residual) || continue
            fname = bm.name
            f_pair = get(mnsq_post.f_map, fname, nothing)
            for (j, lvl) in enumerate(bm.levels)
                m_idx = bm.model_range[j]
                in_m = f_pair === nothing ? NaN : f_pair[1][j]
                out_m = f_pair === nothing ? NaN : f_pair[2][j]
                push!(facets_out, (;
                    facet = String(fname),
                    element = lvl,
                    measure = xi_mean[m_idx],
                    se = xi_sd[m_idx],
                    infit_mnsq = in_m,
                    infit_z = NaN,
                    outfit_mnsq = out_m,
                    outfit_z = NaN,
                    extreme_flag = get(f_ext_dir, (fname, lvl), 0),
                ))
            end
        end

        for bm in step_bms
            crit_lbl = mod_upper == "RSM" ? "ALL" : string(bm.group_level)
            for (h, m_idx) in enumerate(bm.model_range)
                push!(steps_out, (;
                    criterion = crit_lbl,
                    step = h,
                    measure = xi_mean[m_idx],
                    se = xi_sd[m_idx],
                ))
            end
        end

        s_label = person_score_method === :auto ? "NUTS_MEAN" : uppercase(String(person_score_method))
        for p in 1:P
            in_m = mnsq_post.p_in[p]
            out_m = mnsq_post.p_out[p]
            se_p = th_sd[p]
            rse_p = (isfinite(se_p) && isfinite(in_m)) ? se_p * max(1.0, sqrt(max(in_m, 0.0))) : se_p
            push!(person_out, (;
                person = t.people[p],
                measure = th_mean[p],
                se = se_p,
                real_se = rse_p,
                fair_m = fair_m_post[p],
                infit_mnsq = in_m,
                infit_z = NaN,
                outfit_mnsq = out_m,
                outfit_z = NaN,
                extreme_flag = _extreme_flag_int(p_ext[p]),
                score_method = s_label,
            ))
        end
    else
        throw(ArgumentError("unsupported fit type $(typeof(fit)) for write_exchange_run"))
    end

    # Write `facets.csv`
    open(joinpath(odir, "facets.csv"), "w") do io
        println(io, join(_EXCHANGE_FACETS_HEADER, ','))
        for row in facets_out
            println(io, join((_csv_fmt(getproperty(row, Symbol(k))) for k in _EXCHANGE_FACETS_HEADER), ','))
        end
    end

    # Write `steps.csv`
    open(joinpath(odir, "steps.csv"), "w") do io
        println(io, join(_EXCHANGE_STEPS_HEADER, ','))
        for row in steps_out
            println(io, join((_csv_fmt(getproperty(row, Symbol(k))) for k in _EXCHANGE_STEPS_HEADER), ','))
        end
    end

    # Write `person.csv`
    open(joinpath(odir, "person.csv"), "w") do io
        println(io, join(_EXCHANGE_PERSON_HEADER, ','))
        for row in person_out
            println(io, join((_csv_fmt(getproperty(row, Symbol(k))) for k in _EXCHANGE_PERSON_HEADER), ','))
        end
    end

    # Write optional `contrast.csv`
    if contrast_rows !== nothing
        open(joinpath(odir, "contrast.csv"), "w") do io
            println(io, join(_EXCHANGE_CONTRAST_HEADER, ','))
            for row in contrast_rows
                println(io, join((_csv_fmt(get(row, Symbol(k), nothing)) for k in _EXCHANGE_CONTRAST_HEADER), ','))
            end
        end
    end

    # Write `meta.json` (recording exact applied settings)
    extra_dict["model_type"] = mod_upper
    if fit isa _ROOT.FrequentistMFRM.Fit
        extra_dict["zstd_whexact"] = zwhex
        extra_dict["zstd_cap"] = zcap_f
    end
    meta = Dict{String,Any}(
        "schema_version" => EXCHANGE_SCHEMA_VERSION,
        "engine" => String(engine),
        "engine_version" => string(pkgversion(_ROOT)),
        "estimator" => String(estimator),
        "case_id" => String(case_id),
        "input_sha256" => lowercase(String(input_sha256)),
        "status" => status_str,
        "converged" => converged_flag,
        "elapsed_sec" => el_sec,
        "n_obs_used" => n_obs_used,
        "warnings" => warnings_out,
        "host_os" => "$(Sys.KERNEL)-$(Sys.ARCH)",
        "timestamp_utc" => _ROOT.Dates.format(_ROOT.Dates.now(_ROOT.Dates.UTC), "yyyy-mm-ddTHH:MM:SSZ"),
        "extra" => extra_dict,
    )
    open(joinpath(odir, "meta.json"), "w") do io
        _ROOT.JSON3.pretty(io, meta)
        println(io)
    end

    return (;
        run_dir = odir,
        meta_path = joinpath(odir, "meta.json"),
        facets_path = joinpath(odir, "facets.csv"),
        steps_path = joinpath(odir, "steps.csv"),
        person_path = joinpath(odir, "person.csv"),
        contrast_path = contrast_rows === nothing ? nothing : joinpath(odir, "contrast.csv"),
        status = status_str,
        converged = converged_flag,
    )
end

"""
    read_exchange_run(run_dir)

Read an `Exchange Schema v1.0` run output directory (`meta.json`, `facets.csv`,
`steps.csv`, `person.csv`, and optional `contrast.csv`) into typed Julia tables.
"""
function read_exchange_run(run_dir::AbstractString)
    rdir = abspath(run_dir)
    isdir(rdir) || throw(ArgumentError("Exchange run directory does not exist: $rdir"))
    meta_path = joinpath(rdir, "meta.json")
    isfile(meta_path) || throw(ArgumentError("missing meta.json in $rdir"))
    meta = _ROOT.JSON3.read(read(meta_path, String))

    f_csv = _read_simple_csv(joinpath(rdir, "facets.csv"))
    f_idx = Dict(nm => i for (i, nm) in enumerate(f_csv.header))
    facets = [
        (;
            facet = strip(r[f_idx["facet"]]),
            element = strip(r[f_idx["element"]]),
            measure = _parse_opt_float(r[f_idx["measure"]]),
            se = _parse_opt_float(r[f_idx["se"]]),
            infit_mnsq = _parse_opt_float(r[f_idx["infit_mnsq"]]),
            infit_z = _parse_opt_float(r[f_idx["infit_z"]]),
            outfit_mnsq = _parse_opt_float(r[f_idx["outfit_mnsq"]]),
            outfit_z = _parse_opt_float(r[f_idx["outfit_z"]]),
            extreme_flag = isempty(strip(r[f_idx["extreme_flag"]])) ? 0 : parse(Int, strip(r[f_idx["extreme_flag"]])),
        ) for r in f_csv.rows
    ]

    s_csv = _read_simple_csv(joinpath(rdir, "steps.csv"))
    s_idx = Dict(nm => i for (i, nm) in enumerate(s_csv.header))
    steps = [
        (;
            criterion = strip(r[s_idx["criterion"]]),
            step = parse(Int, strip(r[s_idx["step"]])),
            measure = _parse_opt_float(r[s_idx["measure"]]),
            se = _parse_opt_float(r[s_idx["se"]]),
        ) for r in s_csv.rows
    ]

    p_csv = _read_simple_csv(joinpath(rdir, "person.csv"))
    p_idx = Dict(nm => i for (i, nm) in enumerate(p_csv.header))
    persons = [
        (;
            person = strip(r[p_idx["person"]]),
            measure = _parse_opt_float(r[p_idx["measure"]]),
            se = _parse_opt_float(r[p_idx["se"]]),
            real_se = _parse_opt_float(r[p_idx["real_se"]]),
            fair_m = _parse_opt_float(r[p_idx["fair_m"]]),
            infit_mnsq = _parse_opt_float(r[p_idx["infit_mnsq"]]),
            infit_z = _parse_opt_float(r[p_idx["infit_z"]]),
            outfit_mnsq = _parse_opt_float(r[p_idx["outfit_mnsq"]]),
            outfit_z = _parse_opt_float(r[p_idx["outfit_z"]]),
            extreme_flag = isempty(strip(r[p_idx["extreme_flag"]])) ? 0 : parse(Int, strip(r[p_idx["extreme_flag"]])),
            score_method = strip(r[p_idx["score_method"]]),
        ) for r in p_csv.rows
    ]

    c_path = joinpath(rdir, "contrast.csv")
    contrasts = if isfile(c_path)
        c_csv = _read_simple_csv(c_path)
        c_idx = Dict(nm => i for (i, nm) in enumerate(c_csv.header))
        [
            (;
                contrast_id = strip(r[c_idx["contrast_id"]]),
                target_rater = strip(r[c_idx["target_rater"]]),
                group_a = strip(r[c_idx["group_a"]]),
                group_b = strip(r[c_idx["group_b"]]),
                estimate = _parse_opt_float(r[c_idx["estimate"]]),
                se = _parse_opt_float(r[c_idx["se"]]),
                stat = _parse_opt_float(r[c_idx["stat"]]),
                df = _parse_opt_float(r[c_idx["df"]]),
                p_value = _parse_opt_float(r[c_idx["p_value"]]),
                ci_low = _parse_opt_float(r[c_idx["ci_low"]]),
                ci_high = _parse_opt_float(r[c_idx["ci_high"]]),
                method = strip(r[c_idx["method"]]),
                identifiable = _parse_opt_bool(r[c_idx["identifiable"]]),
            ) for r in c_csv.rows
        ]
    else
        nothing
    end

    return (; run_dir = rdir, meta, facets, steps, persons, contrasts)
end

"""
    validate_exchange_run(run_dir; require_contrast = false, sum_tol = 1e-4)

Validate that `run_dir` conforms to `Exchange Schema v1.0` headers, status vocabulary,
and sum-to-zero facet/step identification constraints.
"""
function validate_exchange_run(
        run_dir::AbstractString;
        require_contrast::Bool = false,
        sum_tol::Real = 1e-4)
    issues = String[]
    rdir = abspath(run_dir)
    for fn in ("meta.json", "facets.csv", "steps.csv", "person.csv")
        isfile(joinpath(rdir, fn)) || push!(issues, "missing required file $fn")
    end
    require_contrast && !isfile(joinpath(rdir, "contrast.csv")) &&
        push!(issues, "missing required file contrast.csv")
    !isempty(issues) && return (; valid = false, issues)

    f_hdr = Tuple(_read_simple_csv(joinpath(rdir, "facets.csv")).header)
    f_hdr == _EXCHANGE_FACETS_HEADER || push!(issues, "facets.csv header mismatch: $f_hdr")
    s_hdr = Tuple(_read_simple_csv(joinpath(rdir, "steps.csv")).header)
    s_hdr == _EXCHANGE_STEPS_HEADER || push!(issues, "steps.csv header mismatch: $s_hdr")
    p_hdr = Tuple(_read_simple_csv(joinpath(rdir, "person.csv")).header)
    p_hdr == _EXCHANGE_PERSON_HEADER || push!(issues, "person.csv header mismatch: $p_hdr")
    if isfile(joinpath(rdir, "contrast.csv"))
        c_hdr = Tuple(_read_simple_csv(joinpath(rdir, "contrast.csv")).header)
        c_hdr == _EXCHANGE_CONTRAST_HEADER || push!(issues, "contrast.csv header mismatch: $c_hdr")
    end
    !isempty(issues) && return (; valid = false, issues)

    parsed = read_exchange_run(rdir)
    meta = parsed.meta
    String(get(meta, :schema_version, "")) == EXCHANGE_SCHEMA_VERSION ||
        push!(issues, "meta.json schema_version != $(EXCHANGE_SCHEMA_VERSION)")
    String(get(meta, :status, "")) in ("ok", "nonconverged", "unidentified", "error", "unsupported") ||
        push!(issues, "invalid meta.json status $(get(meta, :status, nothing))")

    # Verify sum-to-zero constraints per facet and per step criterion
    by_facet = Dict{String,Vector{Float64}}()
    for r in parsed.facets
        isfinite(r.measure) && push!(get!(by_facet, r.facet, Float64[]), r.measure)
    end
    for (fn, vals) in by_facet
        abs(sum(vals)) <= Float64(sum_tol) ||
            push!(issues, "facet $(repr(fn)) sum $(sum(vals)) exceeds tolerance $sum_tol")
    end

    by_crit = Dict{String,Vector{Float64}}()
    for r in parsed.steps
        isfinite(r.measure) && push!(get!(by_crit, r.criterion, Float64[]), r.measure)
    end
    for (cn, vals) in by_crit
        abs(sum(vals)) <= Float64(sum_tol) ||
            push!(issues, "steps for criterion $(repr(cn)) sum $(sum(vals)) exceeds tolerance $sum_tol")
    end

    return (; valid = isempty(issues), issues, run = parsed)
end

"""
    compare_exchange_runs(run_a, run_b; target_rater = "1")

Compute head-to-head parity metrics (`max_abs_diff`, `rmse`, `cor`) between two
`Exchange Schema v1.0` run directories across `rater`, `criterion`, `steps`, `person`
(interior and all finite), `fair_m`, and optional `contrast.csv`.
"""
function compare_exchange_runs(
        run_a::AbstractString,
        run_b::AbstractString;
        target_rater::AbstractString = "1")
    a = read_exchange_run(run_a)
    b = read_exchange_run(run_b)

    function _diff_stats(va::Vector{Float64}, vb::Vector{Float64})
        mask = [isfinite(va[i]) && isfinite(vb[i]) for i in eachindex(va)]
        n_m = count(mask)
        n_m == 0 && return (; n = 0, max_abs_diff = NaN, rmse = NaN, cor = NaN)
        da = va[mask] .- vb[mask]
        c_val = n_m >= 2 && _ROOT.Statistics.std(va[mask]) > 0 && _ROOT.Statistics.std(vb[mask]) > 0 ?
            _ROOT.Statistics.cor(va[mask], vb[mask]) : NaN
        return (;
            n = n_m,
            max_abs_diff = maximum(abs, da),
            rmse = sqrt(_ROOT.Statistics.mean(abs2, da)),
            cor = c_val,
        )
    end

    function _facet_vec(parsed, fname::String)
        rows = sort!([r for r in parsed.facets if r.facet == fname]; by = r -> tryparse(Int, r.element) === nothing ? r.element : lpad(r.element, 8, '0'))
        return [r.measure for r in rows], [r.se for r in rows]
    end

    ra_m, ra_se = _facet_vec(a, "rater")
    rb_m, rb_se = _facet_vec(b, "rater")
    ca_m, ca_se = _facet_vec(a, "criterion")
    cb_m, cb_se = _facet_vec(b, "criterion")

    sa = sort(a.steps; by = r -> (r.criterion, r.step))
    sb = sort(b.steps; by = r -> (r.criterion, r.step))
    pa = sort(a.persons; by = r -> tryparse(Int, r.person) === nothing ? r.person : lpad(r.person, 8, '0'))
    pb = sort(b.persons; by = r -> tryparse(Int, r.person) === nothing ? r.person : lpad(r.person, 8, '0'))

    int_mask = [pa[i].extreme_flag == 0 && pb[i].extreme_flag == 0 for i in eachindex(pa)]
    pa_int = [pa[i].measure for i in eachindex(pa) if int_mask[i]]
    pb_int = [pb[i].measure for i in eachindex(pb) if int_mask[i]]

    dff_cmp = if a.contrasts !== nothing && b.contrasts !== nothing
        ca_r = findfirst(r -> r.target_rater == String(target_rater), a.contrasts)
        cb_r = findfirst(r -> r.target_rater == String(target_rater), b.contrasts)
        if ca_r !== nothing && cb_r !== nothing
            ra_c = a.contrasts[ca_r]
            rb_c = b.contrasts[cb_r]
            (;
                estimate_diff = abs(ra_c.estimate - rb_c.estimate),
                se_diff = (isfinite(ra_c.se) && isfinite(rb_c.se)) ? abs(ra_c.se - rb_c.se) : NaN,
                stat_diff = (isfinite(ra_c.stat) && isfinite(rb_c.stat)) ? abs(ra_c.stat - rb_c.stat) : NaN,
                estimate_a = ra_c.estimate,
                estimate_b = rb_c.estimate,
                se_a = ra_c.se,
                se_b = rb_c.se,
                stat_a = ra_c.stat,
                stat_b = rb_c.stat,
            )
        else
            nothing
        end
    else
        nothing
    end

    return (;
        rater = _diff_stats(ra_m, rb_m),
        rater_se = length(ra_se) == length(rb_se) ? _diff_stats(ra_se, rb_se) : nothing,
        criterion = _diff_stats(ca_m, cb_m),
        criterion_se = length(ca_se) == length(cb_se) ? _diff_stats(ca_se, cb_se) : nothing,
        steps = length(sa) == length(sb) ? _diff_stats([r.measure for r in sa], [r.measure for r in sb]) : nothing,
        person_all = length(pa) == length(pb) ? _diff_stats([r.measure for r in pa], [r.measure for r in pb]) : nothing,
        person_interior = _diff_stats(pa_int, pb_int),
        person_se_interior = _diff_stats(
            [pa[i].se for i in eachindex(pa) if int_mask[i]],
            [pb[i].se for i in eachindex(pb) if int_mask[i]],
        ),
        fair_m = length(pa) == length(pb) ? _diff_stats([r.fair_m for r in pa], [r.fair_m for r in pb]) : nothing,
        contrast = dff_cmp,
    )
end

"""
    evaluate_exchange_case(run_dir, truth; target_rater = "1")

Evaluate an `Exchange Schema v1.0` run output directory against a parsed `truth.json`
ground-truth object, returning RMSE, bias, and nominal 95% coverage across `person`,
`fair_m`, `rater`, `criterion`, `steps`, and optional `contrast.csv` DFF target.
"""
function evaluate_exchange_case(
        run_dir::AbstractString,
        truth;
        target_rater::AbstractString = "1")
    parsed = read_exchange_run(run_dir)
    z95 = 1.959963984540054

    true_theta = Float64.(collect(hasproperty(truth, :person_ability) ? truth.person_ability : truth.true_theta))
    true_fair = Float64.(collect(truth.true_fair_m))
    true_rater = Float64.(collect(hasproperty(truth, :rater_severity) ? truth.rater_severity : truth.true_rater))
    true_crit = Float64.(collect(hasproperty(truth, :criterion_difficulty) ? truth.criterion_difficulty : truth.true_criterion))

    pa = sort(parsed.persons; by = r -> parse(Int, r.person))
    ra = sort([r for r in parsed.facets if r.facet == "rater"]; by = r -> parse(Int, r.element))
    ca = sort([r for r in parsed.facets if r.facet == "criterion"]; by = r -> parse(Int, r.element))

    fin_p = [i for i in eachindex(pa) if isfinite(pa[i].measure)]
    p_rmse = isempty(fin_p) ? NaN : sqrt(_ROOT.Statistics.mean((pa[i].measure - true_theta[i])^2 for i in fin_p))
    p_cov_idx = [i for i in fin_p if isfinite(pa[i].se) && pa[i].se > 0]
    p_cov = isempty(p_cov_idx) ? NaN : _ROOT.Statistics.mean(
        abs(pa[i].measure - true_theta[i]) <= z95 * pa[i].se for i in p_cov_idx)

    fin_f = [i for i in eachindex(pa) if isfinite(pa[i].fair_m)]
    fair_rmse = isempty(fin_f) ? NaN : sqrt(_ROOT.Statistics.mean((pa[i].fair_m - true_fair[i])^2 for i in fin_f))

    r_rmse = sqrt(_ROOT.Statistics.mean((ra[i].measure - true_rater[i])^2 for i in eachindex(true_rater)))
    c_rmse = sqrt(_ROOT.Statistics.mean((ca[i].measure - true_crit[i])^2 for i in eachindex(true_crit)))

    dff_eval = if parsed.contrasts !== nothing
        idx_c = findfirst(r -> r.target_rater == String(target_rater), parsed.contrasts)
        if idx_c !== nothing
            rc = parsed.contrasts[idx_c]
            true_dff = hasproperty(truth, :dff_effect) ? Float64(truth.dff_effect) : 0.0
            ci_lo = isfinite(rc.ci_low) ? rc.ci_low : (isfinite(rc.se) ? rc.estimate - z95 * rc.se : NaN)
            ci_hi = isfinite(rc.ci_high) ? rc.ci_high : (isfinite(rc.se) ? rc.estimate + z95 * rc.se : NaN)
            covered = (isfinite(ci_lo) && isfinite(ci_hi)) ? (ci_lo <= true_dff <= ci_hi) : missing
            reject_05 = isfinite(rc.p_value) ? (rc.p_value < 0.05) :
                ((isfinite(ci_lo) && isfinite(ci_hi)) ? !(ci_lo <= 0.0 <= ci_hi) : missing)
            (;
                target_rater = String(target_rater),
                true_dff,
                estimate = rc.estimate,
                bias = rc.estimate - true_dff,
                abs_error = abs(rc.estimate - true_dff),
                se = rc.se,
                ci_low = ci_lo,
                ci_high = ci_hi,
                ci95_width = (isfinite(ci_lo) && isfinite(ci_hi)) ? (ci_hi - ci_lo) : NaN,
                covered_95 = covered,
                reject_zero_05 = reject_05,
                p_value = rc.p_value,
                stat = rc.stat,
            )
        else
            nothing
        end
    else
        nothing
    end

    return (;
        case_id = String(get(parsed.meta, :case_id, "")),
        estimator = String(get(parsed.meta, :estimator, "")),
        status = String(get(parsed.meta, :status, "")),
        converged = Bool(get(parsed.meta, :converged, false)),
        elapsed_sec = Float64(get(parsed.meta, :elapsed_sec, NaN)),
        person_rmse = p_rmse,
        person_ci95_cov = p_cov,
        fair_m_rmse = fair_rmse,
        rater_rmse = r_rmse,
        criterion_rmse = c_rmse,
        dff = dff_eval,
    )
end
