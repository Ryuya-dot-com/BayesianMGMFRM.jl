# Explicit-Role Stan Post-Estimation / CmdStan Adapter & Portable Joint-Draw Handoff (FF4b)
#
# Strict design rules:
# 1. Zero arbitrary `.stan` syntax parsing and zero implicit variable-name guessing:
#    every extracted parameter, facet block, fixed anchor, `log_lik`, and `log_prior`
#    column is declared explicitly by the caller via `roles`.
# 2. Full reproducibility: SHA-256 digests are recorded for `.stan` sources, `data.json`,
#    compiled executables, CmdStan `.csv` chain outputs, and portable JSON handoffs;
#    chain seeds, chain IDs, and iteration indices are strictly verified and preserved.

module StanAdapter

import ..BayesianMGMFRM as B
using Dates
using JSON3
using LinearAlgebra
using Random
using Serialization
using SHA
using Statistics

const FIT_SCHEMA = "bayesianmgmfrm.stan_adapter_fit.v1"
const REPORT_SCHEMA = "bayesianmgmfrm.stan_adapter_report.v1"
const COMPARISON_SCHEMA = "bayesianmgmfrm.stan_adapter_comparison.v1"
const PRIOR_SENSITIVITY_SCHEMA = "bayesianmgmfrm.stan_adapter_prior_sensitivity.v1"

struct Fit
    record::NamedTuple
end

function Base.show(io::IO, f::Fit)
    r = f.record
    s = r.summary
    print(io, "BayesianMGMFRM.StanAdapter.Fit(chains=", s.n_chains,
        ", draws_per_chain=", s.draws_per_chain,
        ", parameters=", s.n_parameters,
        ", has_log_lik=", s.has_log_lik,
        ", has_log_prior=", s.has_log_prior, ")")
end

_sha256_bytes(b) = bytes2hex(sha256(b))
_sha256_file(p::AbstractString) = open(io -> bytes2hex(sha256(io)), p, "r")

function _parse_csv_flexible(path::AbstractString; warmup::Int = 0)
    warmup >= 0 || throw(ArgumentError("warmup must be >= 0"))
    isfile(path) || throw(ArgumentError("Stan CSV file does not exist: $path"))
    header = nothing
    rows = Vector{Vector{Float64}}()
    adaptation_end = nothing
    for line in eachline(path)
        stripped = strip(line)
        isempty(stripped) && continue
        if warmup > 0 && stripped == "# Adaptation terminated"
            adaptation_end === nothing ||
                throw(B.CmdStanError(:output_parse, :warmup_boundary_mismatch, "duplicate # Adaptation terminated in $path"))
            adaptation_end = length(rows)
        end
        startswith(stripped, '#') && continue
        fields = split(stripped, ',')
        if header === nothing
            header = String.(strip.(fields))
            allunique(header) ||
                throw(B.CmdStanError(:output_parse, :duplicate_columns, "Stan CSV $path contains duplicate column names"))
            continue
        end
        length(fields) == length(header) ||
            throw(B.CmdStanError(:output_parse, :column_count_mismatch,
                "Stan CSV $path row $(length(rows) + 1) has $(length(fields)) columns; expected $(length(header))"))
        push!(rows, [B._cmdstan_parse_number(v, length(rows) + 1, col) for (col, v) in pairs(fields)])
    end
    header === nothing && throw(B.CmdStanError(:output_parse, :header_missing, "Stan CSV $path has no header"))
    if warmup > 0
        adaptation_end == warmup ||
            throw(B.CmdStanError(:output_parse, :warmup_boundary_mismatch,
                "Stan CSV $path warmup boundary ($adaptation_end) does not match warmup = $warmup"))
        length(rows) > warmup ||
            throw(B.CmdStanError(:output_parse, :draw_count_mismatch, "Stan CSV $path has no post-warmup draws"))
        mat = reduce(vcat, permutedims.(rows))
        return (; header, values = mat[(warmup + 1):end, :], warmup_values = mat[1:warmup, :])
    end
    isempty(rows) && throw(B.CmdStanError(:output_parse, :draw_count_mismatch, "Stan CSV $path contains zero draw rows"))
    return (; header, values = reduce(vcat, permutedims.(rows)), warmup_values = zeros(Float64, 0, length(header)))
end

function _normalize_roles(roles, header::Vector{String})
    roles isa Union{NamedTuple, AbstractDict} ||
        throw(ArgumentError("roles must be a NamedTuple or Dict declaring explicit Stan column mappings (at minimum `parameters = ...`)"))
    haskey(roles, :parameters) ||
        throw(ArgumentError("roles must explicitly declare `parameters` (either a Vector of Stan column names or a NamedTuple/Pairs of block => columns); implicit variable-name guessing is forbidden"))

    raw_params = roles[:parameters]
    label_map = Dict{String,String}()
    for lkey in (:labels, :parameter_labels)
        if haskey(roles, lkey) && roles[lkey] !== nothing
            lm = roles[lkey]
            for (k, v) in (lm isa Union{AbstractDict, NamedTuple} ? pairs(lm) : lm)
                ks = String(strip(String(k))); vs = String(strip(String(v)))
                !isempty(ks) && !isempty(vs) || throw(ArgumentError("parameter label mappings must be non-empty strings"))
                label_map[ks] = vs
            end
        end
    end

    # Optional structurally fixed reference anchors (`roles.fixed = (rater = ["rater.1" => 0.0],)` or `roles.fixed_parameters = [...]`)
    raw_fixed_entries = NamedTuple[]
    function _push_fixed!(blk::Symbol, item)
        if item isa Pair
            nm = String(strip(String(first(item))))
            val = Float64(last(item))
            !isempty(nm) && isfinite(val) || throw(ArgumentError("fixed anchor requires non-empty name and finite value"))
            push!(raw_fixed_entries, (; block = blk, name = String(get(label_map, nm, nm)), raw_name = nm, value = val))
        elseif item isa NamedTuple && haskey(item, :name) && haskey(item, :value)
            nm = String(strip(String(item.name)))
            val = Float64(item.value)
            b = Symbol(get(item, :block, blk))
            !isempty(nm) && isfinite(val) || throw(ArgumentError("fixed anchor requires non-empty name and finite value"))
            push!(raw_fixed_entries, (; block = b, name = String(get(label_map, nm, nm)), raw_name = nm, value = val))
        else
            throw(ArgumentError("fixed anchor entries must be `name => value` Pairs or `(; block, name, value)` NamedTuples"))
        end
    end
    for fk in (:fixed, :fixed_parameters)
        if haskey(roles, fk) && roles[fk] !== nothing
            fin = roles[fk]
            if fin isa Union{NamedTuple, AbstractDict}
                for (blk_k, items) in pairs(fin)
                    if items isa Union{AbstractVector, Tuple}
                        for it in items; _push_fixed!(Symbol(blk_k), it); end
                    else
                        _push_fixed!(Symbol(blk_k), items)
                    end
                end
            elseif fin isa Union{AbstractVector, Tuple}
                for it in fin; _push_fixed!(:fixed, it); end
            else
                throw(ArgumentError("roles.$fk must be a NamedTuple/Dict of blocks or a Vector of fixed anchors"))
            end
        end
    end

    col_names = String[]
    display_names = String[]
    blocks = Symbol[]
    csv_fixed_names = Set{String}()

    function append_block!(blk::Symbol, cols)
        cols isa Union{AbstractVector, Tuple} ||
            throw(ArgumentError("parameter columns for block $(repr(blk)) must be a Vector or Tuple of exact Stan CSV column names"))
        for c in cols
            cs = String(strip(String(c)))
            !isempty(cs) || throw(ArgumentError("empty Stan column name in block $(repr(blk))"))
            disp = String(get(label_map, cs, cs))
            fidx = findfirst(x -> x.raw_name == cs || x.name == disp, raw_fixed_entries)
            if !(cs in header)
                if fidx !== nothing
                    fe = raw_fixed_entries[fidx]
                    if fe.block === :fixed
                        raw_fixed_entries[fidx] = merge(fe, (; block = blk))
                    end
                    continue
                end
                throw(ArgumentError("declared Stan parameter column $(repr(cs)) not found in CSV header"))
            end
            cs in col_names && throw(ArgumentError("duplicate Stan parameter column $(repr(cs)) in roles.parameters"))
            push!(col_names, cs)
            push!(display_names, disp)
            push!(blocks, blk)
            if fidx !== nothing
                push!(csv_fixed_names, disp)
                deleteat!(raw_fixed_entries, fidx)
            end
        end
    end

    if raw_params isa Union{AbstractVector{<:AbstractString}, Tuple{Vararg{AbstractString}}}
        append_block!(:parameter, raw_params)
    elseif raw_params isa Union{NamedTuple, AbstractDict}
        for (blk_k, cols) in pairs(raw_params)
            append_block!(Symbol(blk_k), cols)
        end
    elseif raw_params isa AbstractVector{<:Pair}
        for p in raw_params
            append_block!(Symbol(first(p)), last(p))
        end
    else
        throw(ArgumentError("roles.parameters must be a Vector of column names or a NamedTuple/Vector{Pair} mapping block => column names"))
    end
    !isempty(col_names) || throw(ArgumentError("roles.parameters must select at least one Stan parameter column"))

    fixed_entries = NamedTuple[(; block = x.block, name = String(x.name), value = x.value) for x in raw_fixed_entries]
    all_names = String[display_names...; [String(x.name) for x in fixed_entries]...]
    allunique(all_names) || throw(ArgumentError("final parameter and fixed_parameter display names must be unique"))

    # Optional explicit `log_lik` declaration
    ll_spec = nothing
    if haskey(roles, :log_lik) && roles[:log_lik] !== nothing
        ll_in = roles[:log_lik]
        ll_in isa Union{NamedTuple, AbstractDict} && haskey(ll_in, :columns) && haskey(ll_in, :unit) ||
            throw(ArgumentError("roles.log_lik must be a NamedTuple with explicit `columns` and `unit` (e.g., `(columns = [\"log_lik.1\", ...], unit = :rating)`)"))
        unit = Symbol(ll_in[:unit])
        unit in (:rating, :event, :performance, :performance_rater, :profile, :cluster) ||
            throw(ArgumentError("roles.log_lik.unit must be one of (:rating, :event, :performance, :performance_rater, :profile, :cluster); got $(repr(unit))"))
        ll_cols = String[String(strip(String(c))) for c in ll_in[:columns]]
        !isempty(ll_cols) && allunique(ll_cols) ||
            throw(ArgumentError("roles.log_lik.columns must be non-empty and unique"))
        for c in ll_cols
            c in header || throw(ArgumentError("declared log_lik column $(repr(c)) not found in CSV header"))
        end
        obs_ids = haskey(ll_in, :observation_ids) && ll_in[:observation_ids] !== nothing ?
            [String(x) for x in ll_in[:observation_ids]] : ["$(unit)_$i" for i in eachindex(ll_cols)]
        length(obs_ids) == length(ll_cols) && allunique(obs_ids) ||
            throw(ArgumentError("roles.log_lik.observation_ids must have length $(length(ll_cols)) with unique IDs"))
        dataset_id = String(get(ll_in, :dataset_id, "stan_dataset"))
        binding = haskey(ll_in, :observation_binding) && ll_in[:observation_binding] !== nothing ?
            String(ll_in[:observation_binding]) :
            B._cache_hash((; unit, dataset_id, observation_ids = obs_ids))
        ll_spec = (; columns = ll_cols, unit, dataset_id, observation_ids = obs_ids, observation_binding = binding)
    end

    # Optional explicit `log_prior` and `alt_log_priors`
    lp_col = nothing
    if haskey(roles, :log_prior) && roles[:log_prior] !== nothing
        c = String(strip(String(roles[:log_prior])))
        c in header || throw(ArgumentError("declared log_prior column $(repr(c)) not found in CSV header"))
        lp_col = c
    end

    alt_lp_cols = Pair{Symbol,String}[]
    if haskey(roles, :alt_log_priors) && roles[:alt_log_priors] !== nothing
        alp = roles[:alt_log_priors]
        for (k, v) in (alp isa Union{AbstractDict, NamedTuple} ? pairs(alp) : alp)
            cs = String(strip(String(v)))
            cs in header || throw(ArgumentError("declared alt_log_priors column $(repr(cs)) for $(repr(k)) not found in CSV header"))
            push!(alt_lp_cols, Symbol(k) => cs)
        end
    end

    return (;
        stan_columns = col_names,
        display_names,
        blocks,
        fixed_entries,
        csv_fixed_names,
        log_lik = ll_spec,
        log_prior_column = lp_col,
        alt_log_prior_columns = alt_lp_cols,
    )
end

"""
    StanAdapter.import_csv(csv_paths; roles, warmup = 0, seed = missing, metadata = NamedTuple(), warnings = String[])

Import one or more existing CmdStan `.csv` chain output files into a verified
`StanAdapter.Fit` using explicit `roles` mappings (no `.stan` syntax parsing and
no implicit column-name guessing). Every source `.csv` file's SHA-256 digest,
NUTS sampler telemetry (`lp__`, `accept_stat__`, `stepsize__`, `treedepth__`,
`n_leapfrog__`, `divergent__`, `energy__`), and `(chain, iteration)` ordering
are validated and sealed into `content_hash`.
"""
function import_csv(csv_paths::Union{AbstractString, AbstractVector{<:AbstractString}};
        roles,
        warmup::Int = 0,
        recorded_warmup::Union{Nothing,Int} = nothing,
        seed = missing,
        stan_source_sha256 = missing,
        data_json_sha256 = missing,
        executable_sha256 = missing,
        cmdstan_version = missing,
        metadata::NamedTuple = NamedTuple(),
        warnings::AbstractVector{<:AbstractString} = String[])
    paths = csv_paths isa AbstractString ? [abspath(csv_paths)] : [abspath(p) for p in csv_paths]
    !isempty(paths) && allunique(paths) ||
        throw(ArgumentError("supply one or more distinct CmdStan CSV file paths"))
    csv_hashes = [_sha256_file(p) for p in paths]
    parsed_chains = [_parse_csv_flexible(p; warmup) for p in paths]

    header = parsed_chains[1].header
    ndraws = size(parsed_chains[1].values, 1)
    n_chains = length(paths)
    for (c, pc) in enumerate(parsed_chains)
        pc.header == header ||
            throw(B.CmdStanError(:output_parse, :header_mismatch, "Chain $c CSV header differs from chain 1"))
        size(pc.values, 1) == ndraws ||
            throw(B.CmdStanError(:output_parse, :draw_count_mismatch,
                "Chain $c has $(size(pc.values, 1)) post-warmup draws; chain 1 has $ndraws"))
    end

    norm_roles = _normalize_roles(roles, header)
    col_idx = Dict(h => i for (i, h) in enumerate(header))
    req_nuts = ("lp__", "accept_stat__", "stepsize__", "treedepth__", "n_leapfrog__", "divergent__", "energy__")
    for nm in req_nuts
        haskey(col_idx, nm) ||
            throw(B.CmdStanError(:output_parse, :required_column_missing, "Stan CSV is missing NUTS diagnostic column $nm"))
    end

    p_indices = [col_idx[c] for c in norm_roles.stan_columns]
    n_free = length(p_indices)
    n_fixed = length(norm_roles.fixed_entries)
    n_total_params = n_free + n_fixed
    total_draws = n_chains * ndraws

    draws = Matrix{Float64}(undef, total_draws, n_total_params)
    logdensities = Vector{Float64}(undef, total_draws)
    chain_ids = Vector{Int}(undef, total_draws)
    iterations = Vector{Int}(undef, total_draws)
    sampler_stats = Vector{NamedTuple}(undef, total_draws)
    chain_acceptance = Vector{Float64}(undef, n_chains)

    ll_mat = norm_roles.log_lik === nothing ? nothing :
        Matrix{Float64}(undef, total_draws, length(norm_roles.log_lik.columns))
    ll_indices = norm_roles.log_lik === nothing ? Int[] : [col_idx[c] for c in norm_roles.log_lik.columns]
    lp_vec = norm_roles.log_prior_column === nothing ? nothing : Vector{Float64}(undef, total_draws)
    lp_idx = norm_roles.log_prior_column === nothing ? 0 : col_idx[norm_roles.log_prior_column]
    alt_lp_vecs = Dict{Symbol,Vector{Float64}}(k => Vector{Float64}(undef, total_draws) for (k, _) in norm_roles.alt_log_prior_columns)

    row_cursor = 0
    for (c, pc) in enumerate(parsed_chains)
        vals = pc.values
        acc_col = view(vals, :, col_idx["accept_stat__"])
        all(isfinite, acc_col) || throw(B.CmdStanError(:output_parse, :nonfinite_sampler_statistic, "non-finite accept_stat__ in chain $c"))
        chain_acceptance[c] = mean(acc_col)

        for it in 1:ndraws
            row_cursor += 1
            chain_ids[row_cursor] = c
            iterations[row_cursor] = it
            for j in 1:n_free
                v = vals[it, p_indices[j]]
                isfinite(v) || throw(B.CmdStanError(:output_parse, :nonfinite_draw,
                    "non-finite draw at chain $c iteration $it column $(norm_roles.stan_columns[j])"))
                draws[row_cursor, j] = v
            end
            for j in 1:n_fixed
                draws[row_cursor, n_free + j] = norm_roles.fixed_entries[j].value
            end

            lp_val = vals[it, col_idx["lp__"]]
            acc_v = vals[it, col_idx["accept_stat__"]]
            ss_v = vals[it, col_idx["stepsize__"]]
            td_v = B._cmdstan_integer_stat(vals[it, col_idx["treedepth__"]], "treedepth__")
            lf_v = B._cmdstan_integer_stat(vals[it, col_idx["n_leapfrog__"]], "n_leapfrog__")
            div_v = B._cmdstan_integer_stat(vals[it, col_idx["divergent__"]], "divergent__")
            en_v = vals[it, col_idx["energy__"]]
            all(isfinite, (lp_val, acc_v, ss_v, en_v)) ||
                throw(B.CmdStanError(:output_parse, :nonfinite_sampler_statistic, "non-finite NUTS telemetry at chain $c iteration $it"))
            div_v in (0, 1) || throw(B.CmdStanError(:output_parse, :invalid_sampler_statistic, "divergent__ must be 0 or 1"))

            logdensities[row_cursor] = lp_val
            sampler_stats[row_cursor] = (;
                chain = c,
                iteration = it,
                acceptance_rate = acc_v,
                step_size = ss_v,
                tree_depth = td_v,
                n_steps = lf_v,
                numerical_error = div_v == 1,
                hamiltonian_energy = en_v,
                hamiltonian_energy_error = NaN,
                is_adapt = false,
                max_hamiltonian_energy_error = NaN,
                log_density = lp_val,
            )

            if ll_mat !== nothing
                for (k, cidx) in enumerate(ll_indices)
                    lv = vals[it, cidx]
                    isfinite(lv) || throw(B.CmdStanError(:output_parse, :nonfinite_draw, "non-finite log_lik at chain $c iteration $it"))
                    ll_mat[row_cursor, k] = lv
                end
            end
            if lp_vec !== nothing
                pv = vals[it, lp_idx]
                isfinite(pv) || throw(B.CmdStanError(:output_parse, :nonfinite_draw, "non-finite log_prior at chain $c iteration $it"))
                lp_vec[row_cursor] = pv
            end
            for (k_sym, col_str) in norm_roles.alt_log_prior_columns
                av = vals[it, col_idx[col_str]]
                isfinite(av) || throw(B.CmdStanError(:output_parse, :nonfinite_draw, "non-finite alt_log_prior $(k_sym) at chain $c iteration $it"))
                alt_lp_vecs[k_sym][row_cursor] = av
            end
        end
    end

    all_param_names = String[norm_roles.display_names...; [String(x.name) for x in norm_roles.fixed_entries]...]
    all_blocks = Symbol[norm_roles.blocks...; [Symbol(x.block) for x in norm_roles.fixed_entries]...]
    fixed_names = union(Set{String}([String(x.name) for x in norm_roles.fixed_entries]), norm_roles.csv_fixed_names)

    eff_warmup = something(recorded_warmup, warmup)
    meta_nt = (; pairs(metadata)...)
    if haskey(meta_nt, :adapt_delta) && haskey(meta_nt, :target_accept) &&
            meta_nt[:adapt_delta] !== nothing && meta_nt[:target_accept] !== nothing
        throw(ArgumentError("cannot specify both `adapt_delta` and `target_accept` in StanAdapter.import_csv metadata"))
    end
    if haskey(meta_nt, :max_treedepth) && haskey(meta_nt, :max_depth) &&
            meta_nt[:max_treedepth] !== nothing && meta_nt[:max_depth] !== nothing
        throw(ArgumentError("cannot specify both `max_treedepth` and `max_depth` in StanAdapter.import_csv metadata"))
    end
    max_td_ctrl = Int(something(get(meta_nt, :max_depth, nothing), get(meta_nt, :max_treedepth, nothing), 10))
    ta_ctrl = something(get(meta_nt, :target_accept, nothing), get(meta_nt, :adapt_delta, nothing), missing)
    controls = (;
        backend = :cmdstan_explicit_adapter,
        chains = n_chains,
        warmup = eff_warmup,
        ndraws,
        seed,
        step_size = Float64(mean(st.step_size for st in sampler_stats)),
        max_depth = max_td_ctrl,
        target_accept = ismissing(ta_ctrl) ? missing : Float64(ta_ctrl),
    )
    sampler_rows = B._generalized_candidate_sampler_rows(
        logdensities, iterations, chain_acceptance, sampler_stats, controls, :cmdstan)

    checked_thresh = B._check_diagnostic_thresholds(1.01, 400.0)
    run_nt = (;
        backend = :cmdstan,
        sampler = :nuts,
        controls,
        checked = checked_thresh,
        split_chains_requested = true,
        total_draws,
        nparams = n_total_params,
        chain_ids,
        iterations,
        chain_acceptance,
        draws,
        logdensities,
        sampler_stats,
        sampler_rows,
    )

    provenance = (;
        source_kind = :cmdstan_csv_import,
        csv_basenames = basename.(paths),
        csv_sha256 = csv_hashes,
        stan_source_sha256,
        data_json_sha256,
        executable_sha256,
        cmdstan_version,
        seed,
        julia_version = string(VERSION),
        package_version = string(pkgversion(B)),
        os = string(Sys.KERNEL),
        arch = string(Sys.ARCH),
        metadata,
    )

    summary_nt = (;
        n_chains,
        warmup = eff_warmup,
        draws_per_chain = ndraws,
        total_draws,
        n_parameters = n_total_params,
        n_free_parameters = n_free,
        n_fixed_parameters = n_fixed,
        has_log_lik = ll_mat !== nothing,
        log_lik_unit = ll_mat === nothing ? missing : norm_roles.log_lik.unit,
        n_log_lik_units = ll_mat === nothing ? 0 : size(ll_mat, 2),
        has_log_prior = lp_vec !== nothing,
        alt_log_prior_keys = Tuple(first.(norm_roles.alt_log_prior_columns)),
    )

    alt_lp_nt = NamedTuple{Tuple(first.(norm_roles.alt_log_prior_columns))}(
        Tuple(alt_lp_vecs[first(p)] for p in norm_roles.alt_log_prior_columns)
    )

    body = (;
        schema = FIT_SCHEMA,
        summary = summary_nt,
        parameter_names = all_param_names,
        stan_columns = norm_roles.stan_columns,
        parameter_blocks = all_blocks,
        fixed_parameters = norm_roles.fixed_entries,
        fixed_name_set = sort!(collect(fixed_names)),
        run = run_nt,
        log_lik_meta = norm_roles.log_lik,
        log_lik = ll_mat,
        log_prior_column = norm_roles.log_prior_column,
        log_prior = lp_vec,
        alt_log_priors = alt_lp_nt,
        provenance,
        warnings = String[String(w) for w in warnings],
    )
    digest = B._cache_hash((;
        schema = FIT_SCHEMA,
        parameter_names = all_param_names,
        parameter_blocks = all_blocks,
        fixed_parameters = norm_roles.fixed_entries,
        chain_ids,
        iterations,
        draws,
        logdensities,
        log_lik_meta = norm_roles.log_lik,
        log_lik = ll_mat,
        log_prior = lp_vec,
        provenance_hashes = (; csv_hashes, stan_source_sha256, data_json_sha256, executable_sha256),
    ))
    return Fit(merge(body, (; content_hash = digest)))
end

"""
    StanAdapter.fit_stan(stan_file_or_code; data = NamedTuple(), roles, chains = 4,
        warmup = 1000, ndraws = 1000, seed, target_accept = 0.90, max_depth = 10,
        adapt_delta = nothing, max_treedepth = nothing,
        init_radius = nothing, work_dir = nothing, cmdstan_path = nothing, metadata = NamedTuple())

Compile and sample a user-supplied Stan program through the local CmdStan
toolchain with deterministic integer `seed`, SHA-256 provenance tracking, and
explicit `roles` post-estimation mapping. No `.stan` syntax parsing or variable
guessing is performed. Canonical NUTS controls are `target_accept` (default `0.90`,
mapped to CmdStan `adapt delta`) and `max_depth` (default `10`); Stan/brms names
`adapt_delta` and `max_treedepth` are accepted as aliases and emit an informational
hint pointing to `target_accept` / `max_depth`.
"""
function fit_stan(stan_file_or_code::AbstractString, data; kwargs...)
    return fit_stan(stan_file_or_code; data, kwargs...)
end

function fit_stan(stan_file_or_code::AbstractString;
        data = NamedTuple(),
        roles,
        chains::Int = 4,
        warmup::Int = 1000,
        ndraws::Int = 1000,
        seed::Integer,
        target_accept::Union{Nothing,Real} = nothing,
        adapt_delta::Union{Nothing,Real} = nothing,
        max_depth::Union{Nothing,Int} = nothing,
        max_treedepth::Union{Nothing,Int} = nothing,
        init_radius::Union{Nothing,Real} = nothing,
        output_dir::Union{Nothing,AbstractString} = nothing,
        work_dir::Union{Nothing,AbstractString} = output_dir,
        cmdstan_path::Union{Nothing,AbstractString} = nothing,
        metadata::NamedTuple = NamedTuple())
    chains >= 1 || throw(ArgumentError("chains must be >= 1"))
    warmup >= 1 || throw(ArgumentError("warmup must be >= 1"))
    ndraws >= 1 || throw(ArgumentError("ndraws must be >= 1"))
    seed isa Integer && !(seed isa Bool) && 0 <= seed <= typemax(Int32) ||
        throw(ArgumentError("seed must be a reproducible integer in 0..$(typemax(Int32)) for CmdStan"))
    ta_resolved, md_resolved = B._resolve_stan_nuts_aliases(;
        target_accept, adapt_delta, default_target_accept = 0.90,
        max_depth, max_treedepth, default_max_depth = 10,
        caller = "StanAdapter.fit_stan", backend = :cmdstan)
    0.0 < Float64(ta_resolved) < 1.0 || throw(ArgumentError("target_accept must lie in (0, 1)"))
    md_resolved >= 1 || throw(ArgumentError("max_depth must be >= 1"))
    target_accept = ta_resolved
    max_depth = md_resolved
    if init_radius !== nothing
        init_radius isa Real && !(init_radius isa Bool) && isfinite(init_radius) && init_radius >= 0.0 ||
            throw(ArgumentError("init_radius must be nonnegative and finite when supplied"))
    end

    check = B.cmdstan_backend_check(; cmdstan_path, include_paths = true, require_ready = true)
    for env_var in ("MAKEFILES", "MAKEFLAGS", "GNUMAKEFLAGS")
        isempty(get(ENV, env_var, "")) || throw(B.CmdStanError(
            :model_compile, :unsupported_make_environment, "$env_var must be unset or empty"))
    end
    make_prog = B._cmdstan_configured_program("MAKE", ("make", "gmake"))
    make_prog === nothing && throw(B.CmdStanError(:model_compile, :make_unavailable, "make or gmake not found"))

    is_file = endswith(lowercase(strip(stan_file_or_code)), ".stan") && isfile(stan_file_or_code)
    stan_code = is_file ? read(stan_file_or_code, String) : String(stan_file_or_code)
    isempty(strip(stan_code)) && throw(ArgumentError("Stan model source must not be empty"))
    stan_sha = _sha256_bytes(codeunits(stan_code))

    cache_key = _sha256_bytes(codeunits(string(check.cmdstan_root, ":", check.cmdstan_version, ":", stan_sha)))
    cache_dir = joinpath(tempdir(), "bayesianmgmfrm_stan_exe_cache", cache_key)
    mkpath(cache_dir)
    stem = joinpath(cache_dir, "custom_stan_model")
    stan_path = stem * ".stan"
    exe_path = B._cmdstan_executable_path(stem)
    if !isfile(exe_path)
        write(stan_path, stan_code)
        compile_cmd = Cmd(`$make_prog -f makefile $stem`; dir = check.cmdstan_root)
        B._cmdstan_run(compile_cmd, :model_compile)
    end
    exe_sha = _sha256_file(exe_path)

    run_body = function (dir::String)
        write(joinpath(dir, "custom_stan_model.stan"), stan_code)
        data_path = joinpath(dir, "stan_data.json")
        data_json = JSON3.write(data)
        write(data_path, data_json)
        data_sha = _sha256_bytes(codeunits(data_json))

        csv_paths = String[]
        for c in 1:chains
            out_csv = joinpath(dir, "chain_$(c).csv")
            args = String[
                exe_path,
                "sample",
                "num_samples=$ndraws",
                "num_warmup=$warmup",
                "save_warmup=0",
                "thin=1",
                "adapt",
                "engaged=1",
                "delta=$(Float64(target_accept))",
                "algorithm=hmc",
                "engine=nuts",
                "max_depth=$max_depth",
                "data",
                "file=$data_path",
            ]
            if init_radius !== nothing
                push!(args, "init=$(Float64(init_radius))")
            end
            append!(args, [
                "random",
                "seed=$(Int(seed))",
                "id=$c",
                "output",
                "file=$out_csv",
                "refresh=0",
                "sig_figs=18",
            ])
            B._cmdstan_run(Cmd(Cmd(args); dir = dir), :sampling)
            push!(csv_paths, out_csv)
        end

        meta_merged = merge(metadata, (;
            max_depth,
            target_accept = Float64(target_accept),
            init_radius,
            source_file = is_file ? basename(stan_file_or_code) : :inline_stan_code,
        ))
        return import_csv(csv_paths;
            roles,
            warmup = 0,
            recorded_warmup = warmup,
            seed = Int(seed),
            stan_source_sha256 = stan_sha,
            data_json_sha256 = data_sha,
            executable_sha256 = exe_sha,
            cmdstan_version = check.cmdstan_version,
            metadata = meta_merged)
    end

    if work_dir !== nothing
        wdir = abspath(work_dir)
        if ispath(wdir)
            (isdir(wdir) && isempty(readdir(wdir))) ||
                throw(ArgumentError("work_dir must be a new path or an empty directory to preserve reproducibility: $wdir"))
        else
            mkpath(wdir)
        end
        return run_body(wdir)
    else
        return mktempdir(run_body)
    end
end

function checked(f::Fit)
    r = f.record
    r.schema == FIT_SCHEMA || throw(ArgumentError("unknown StanAdapter fit schema"))
    expected = B._cache_hash((;
        schema = FIT_SCHEMA,
        parameter_names = r.parameter_names,
        parameter_blocks = r.parameter_blocks,
        fixed_parameters = r.fixed_parameters,
        chain_ids = r.run.chain_ids,
        iterations = r.run.iterations,
        draws = r.run.draws,
        logdensities = r.run.logdensities,
        log_lik_meta = r.log_lik_meta,
        log_lik = r.log_lik,
        log_prior = r.log_prior,
        provenance_hashes = (;
            csv_hashes = r.provenance.csv_sha256,
            stan_source_sha256 = r.provenance.stan_source_sha256,
            data_json_sha256 = r.provenance.data_json_sha256,
            executable_sha256 = r.provenance.executable_sha256,
        ),
    ))
    expected == r.content_hash || throw(ArgumentError("StanAdapter.Fit content_hash checksum mismatch"))
    return r
end

function diagnostics(f::Fit)
    r = checked(f)
    run = r.run
    fixed_set = Set{String}(r.fixed_name_set)
    model_rows = B._candidate_mcmc_diagnostic_rows(
        run.draws, r.parameter_names, run.controls.chains;
        parameter_space = :model,
        structurally_fixed_parameters = fixed_set,
        split_chains = run.split_chains_requested,
        rhat_threshold = run.checked.rhat_threshold,
        ess_threshold = run.checked.ess_threshold)
    return (;
        schema = "bayesianmgmfrm.stan_adapter_diagnostics.v1",
        backend = run.backend,
        model = model_rows,
        sampler = deepcopy(run.sampler_rows),
        thresholds = (; run.checked..., minimum_chains = 2),
        provenance = r.provenance,
        warnings = copy(r.warnings),
        scientific_acceptance = false,
    )
end

function qualify(f::Fit;
        max_rhat::Real = 1.01,
        min_ess::Real = 400.0,
        min_bfmi::Union{Nothing,Real} = nothing,
        ebfmi_min::Union{Nothing,Real} = nothing,
        bfmi_min::Union{Nothing,Real} = nothing)
    min_ess isa Bool && throw(ArgumentError("min_ess must be a finite positive real number"))
    checked_th = B._check_diagnostic_thresholds(max_rhat, min_ess)
    resolved_bfmi = B._resolve_bfmi_alias(; min_bfmi, ebfmi_min, bfmi_min, default_min_bfmi = 0.30, caller = "qualify")
    d = diagnostics(f)
    return B._qualify_experimental_diagnostics(d, f.record.run, checked_th, resolved_bfmi)
end

function _select_columns(r::NamedTuple; parameters = nothing)
    chosen = parameters === nothing ? r.parameter_names : [String(p) for p in parameters]
    !isempty(chosen) && allunique(chosen) || throw(ArgumentError("select at least one distinct parameter name"))
    idx = Int[]
    for nm in chosen
        k = findfirst(==(nm), r.parameter_names)
        k === nothing && throw(ArgumentError("unknown StanAdapter parameter $(repr(nm)); inspect parameter_names(fit)"))
        push!(idx, k)
    end
    return (; names = chosen, indices = idx, values = r.run.draws[:, idx],
        blocks = r.parameter_blocks[idx], fixed = Set{String}(r.fixed_name_set))
end

function summary(f::Fit; parameters = nothing, interval::Real = 0.95)
    r = checked(f)
    lo, hi = B._interval_probabilities(Float64(interval))
    sel = _select_columns(r; parameters)
    srows = B._posterior_summary_rows(sel.values, sel.names;
        lower = lo, upper = hi, intervals = (Float64(interval),),
        reference = 0.0, rope = nothing, rope_probability_threshold = 0.95)
    mcse_rows = B._posterior_mcse_rows(sel.values, sel.names, r.run.controls.chains;
        probabilities = (lo, 0.5, hi), parameter_space = :model,
        structurally_fixed_parameters = sel.fixed)
    rows = [
        (;
            parameter = srows[i].parameter,
            block = sel.blocks[i],
            structurally_fixed = srows[i].parameter in sel.fixed,
            mean = srows[i].mean,
            sd = srows[i].sd,
            median = srows[i].median,
            lower = srows[i].lower,
            upper = srows[i].upper,
            mean_mcse = mcse_rows[i].mean_mcse,
            mcse_status = mcse_rows[i].mcse_status,
        ) for i in eachindex(srows)
    ]
    return (;
        schema = "bayesianmgmfrm.stan_adapter_posterior_summary.v1",
        interval = Float64(interval),
        rows,
        source_content_hash = r.content_hash,
        provenance = r.provenance,
        warnings = copy(r.warnings),
        scientific_acceptance = false,
    )
end

function mcse(f::Fit; parameters = nothing, probabilities = (0.025, 0.5, 0.975))
    r = checked(f)
    sel = _select_columns(r; parameters)
    return B._posterior_mcse_rows(sel.values, sel.names, r.run.controls.chains;
        probabilities, parameter_space = :model, structurally_fixed_parameters = sel.fixed)
end

function facet_summary(f::Fit; facet::Symbol = :person, interval::Real = 0.95)
    r = checked(f)
    target = facet === :entity ? :person : facet
    idx = findall(==(target), r.parameter_blocks)
    isempty(idx) && throw(ArgumentError(
        "no parameters declared for block $(repr(facet)); available blocks: $(unique(r.parameter_blocks))"))
    names_f = r.parameter_names[idx]
    sub = summary(f; parameters = names_f, interval)
    return (;
        schema = "bayesianmgmfrm.stan_adapter_facet_summary.v1",
        facet = target,
        interval = Float64(interval),
        n_levels = length(sub.rows),
        rows = sub.rows,
        source_content_hash = r.content_hash,
    )
end

function contrast(f::Fit; left::AbstractString, right::AbstractString, interval::Real = 0.95, rope = nothing)
    r = checked(f)
    left != right || throw(ArgumentError("left and right must name distinct parameters"))
    sel = _select_columns(r; parameters = [String(left), String(right)])
    res = B.posterior_contrast(view(sel.values, :, 1), view(sel.values, :, 2);
        chains = r.run.controls.chains, interval = Float64(interval), rope)
    return (;
        schema = "bayesianmgmfrm.stan_adapter_contrast.v1",
        left = String(left),
        right = String(right),
        conditioning = :joint_posterior_same_draws,
        result = res,
        qualification = qualify(f),
        source_content_hash = r.content_hash,
    )
end

function _cohort_parameters(r::NamedTuple; facet::Symbol = :person, parameters = nothing, allow_fixed::Bool = false)
    fixed_set = Set{String}(r.fixed_name_set)
    chosen = if parameters !== nothing
        [String(p) for p in parameters]
    else
        target = facet === :entity ? :person : facet
        idx = [i for i in eachindex(r.parameter_names) if r.parameter_blocks[i] === target &&
               (allow_fixed || !(r.parameter_names[i] in fixed_set))]
        isempty(idx) && throw(ArgumentError(
            "no estimated parameters found in block $(repr(target)); pass explicit `parameters = [...]` or declare `$(target) = [...]` in roles.parameters"))
        r.parameter_names[idx]
    end
    sel = _select_columns(r; parameters = chosen)
    if !allow_fixed && any(n -> n in fixed_set, sel.names)
        throw(ArgumentError("fixed anchor parameters cannot be included in cohort ranking/reliability/classification"))
    end
    return sel
end

function ranking(f::Fit; facet::Symbol = :person, parameters = nothing,
        direction::Symbol = :higher, top_k = nothing, interval::Real = 0.90,
        max_rank_cells::Int = 20_000_000)
    r = checked(f)
    direction in (:higher, :lower) || throw(ArgumentError("direction must be :higher or :lower"))
    sel = _cohort_parameters(r; facet, parameters, allow_fixed = false)
    N = length(sel.names)
    N >= 2 || throw(ArgumentError("ranking requires at least two cohort parameters"))
    S = size(sel.values, 1)
    S * N <= max_rank_cells || throw(ArgumentError("selected draw-by-cohort matrix ($(S * N)) exceeds max_rank_cells = $max_rank_cells"))
    if top_k !== nothing
        top_k isa Integer && !(top_k isa Bool) && 1 <= top_k <= N ||
            throw(ArgumentError("top_k must be an integer between 1 and $N"))
    end
    B._interval_probabilities(Float64(interval))
    rk = B._posterior_rank_draws(sel.values, direction, top_k)
    chains = r.run.controls.chains
    rows = map(1:N) do i
        rs = B._posterior_rank_summary(view(rk.ranks, :, i), chains, Float64(interval))
        tk = if top_k === nothing
            nothing
        elseif top_k == N
            (; lower = (; mean = 1.0, mcse = (; value = 0.0, status = :structural_certainty)),
               upper = (; mean = 1.0, mcse = (; value = 0.0, status = :structural_certainty)),
               boundary_tie_probability = (; mean = 0.0, mcse = (; value = 0.0, status = :structural_certainty)))
        else
            c_v = Float64.(view(rk.certain, :, i))
            p_v = Float64.(view(rk.possible, :, i))
            (; lower = B._classification_mean(c_v, chains),
               upper = B._classification_mean(p_v, chains),
               boundary_tie_probability = B._classification_mean(p_v .- c_v, chains))
        end
        (; parameter = sel.names[i], rs..., tie_probability = mean(view(rk.tied, :, i)), top_k_probability = tk)
    end
    return (;
        schema = "bayesianmgmfrm.stan_adapter_ranking.v1",
        direction,
        top_k,
        interval = Float64(interval),
        n_levels = N,
        n_draws = S,
        rows,
        qualification = qualify(f),
        source_content_hash = r.content_hash,
    )
end

function reliability(f::Fit; facet::Symbol = :person, parameters = nothing,
        target::Symbol = :centered, weights = nothing)
    r = checked(f)
    sel = _cohort_parameters(r; facet, parameters, allow_fixed = false)
    N = length(sel.names)
    w = weights === nothing ? ones(Float64, N) : weights
    comp = B._posterior_reliability_components(sel.values, w, target)
    mcse_r = B._posterior_reliability_mcse(comp, r.run.controls.chains)
    return (;
        schema = "bayesianmgmfrm.stan_adapter_reliability.v1",
        target,
        parameters = sel.names,
        n_levels = N,
        n_draws = size(sel.values, 1),
        between_variance = comp.between,
        within_variance = comp.within,
        total_variance = comp.total,
        reliability = comp.reliability,
        mcse = mcse_r,
        qualification = qualify(f),
        source_content_hash = r.content_hash,
    )
end

function classification(f::Fit; cutoff::Real, pass_probability::Real = 0.5,
        facet::Symbol = :person, parameters = nothing, interval::Real = 0.90)
    r = checked(f)
    all(x -> x isa Real && !(x isa Bool) && isfinite(x), (cutoff, pass_probability, interval)) ||
        throw(ArgumentError("cutoff, pass_probability, and interval must be finite real numbers"))
    0.0 < Float64(pass_probability) < 1.0 || throw(ArgumentError("pass_probability must lie strictly in (0, 1)"))
    lo, hi = B._interval_probabilities(Float64(interval))
    sel = _cohort_parameters(r; facet, parameters, allow_fixed = false)
    ev = B._classification_events(sel.values, Float64(cutoff), Float64(pass_probability))
    chains = r.run.controls.chains
    rows = map(eachindex(sel.names)) do i
        vals = view(sel.values, :, i)
        q_ind = Float64.(view(ev.qualifies, :, i))
        q_stat = B._classification_mean(q_ind, chains)
        dec = ev.pass[i] ? :pass : :fail
        err_ind = ev.pass[i] ? (1.0 .- q_ind) : q_ind
        err_stat = B._classification_mean(err_ind, chains)
        (;
            parameter = sel.names[i],
            mean = mean(vals),
            sd = std(vals),
            lower = quantile(vals, lo),
            upper = quantile(vals, hi),
            qualifying_probability = q_stat.mean,
            qualifying_mcse = q_stat.mcse,
            decision = dec,
            error_probability = err_stat.mean,
            error_mcse = err_stat.mcse,
        )
    end
    n_pass = count(ev.pass)
    n_fail = length(ev.pass) - n_pass
    cohort = (;
        n_people = length(sel.names),
        n_pass,
        n_fail,
        expected_false_pass = B._classification_mean(Float64.(ev.false_pass), chains; fixed = n_pass == 0),
        expected_false_fail = B._classification_mean(Float64.(ev.false_fail), chains; fixed = n_fail == 0),
        expected_total_errors = B._classification_mean(Float64.(ev.errors), chains; fixed = isempty(sel.names)),
        any_error_probability = B._classification_mean(Float64.(ev.errors .> 0), chains; fixed = isempty(sel.names)),
    )
    return (;
        schema = "bayesianmgmfrm.stan_adapter_classification.v1",
        cutoff = Float64(cutoff),
        pass_probability = Float64(pass_probability),
        interval = Float64(interval),
        rows,
        cohort,
        qualification = qualify(f),
        source_content_hash = r.content_hash,
    )
end

function _require_log_lik(r::NamedTuple, caller::Symbol)
    r.log_lik !== nothing && r.log_lik_meta !== nothing ||
        throw(ArgumentError("$caller requires an explicit `log_lik = (columns = [...], unit = ...)` declaration in StanAdapter `roles`"))
    return r.log_lik, r.log_lik_meta
end

function waic_report(f::Fit)
    r = checked(f)
    ll, meta = _require_log_lik(r, :waic)
    meta.unit in (:rating, :event) ||
        throw(ArgumentError("waic requires conditionally independent :rating or :event log_lik units; got unit = $(repr(meta.unit)) (use psis_loo or criteria(fit; criteria = (:psis_loo,)))"))
    return merge(B.waic(ll), (; unit = meta.unit, observation_binding = meta.observation_binding,
        observation_ids = copy(meta.observation_ids)))
end

function psis_loo_report(f::Fit; pareto_k_threshold::Real = 0.7)
    r = checked(f)
    ll, meta = _require_log_lik(r, :psis_loo)
    B._check_psis_iterations(r.run.chain_ids, r.run.iterations)
    res = B.psis_loo(ll; chain_ids = r.run.chain_ids, pareto_k_threshold)
    return merge(res, (; unit = meta.unit, observation_binding = meta.observation_binding,
        observation_ids = copy(meta.observation_ids)))
end

function criteria_report(f::Fit; criteria::Tuple = (:waic, :psis_loo), pareto_k_threshold::Real = 0.7)
    r = checked(f)
    ll, meta = _require_log_lik(r, :criteria)
    eff_criteria = (criteria == (:waic, :psis_loo) && !(meta.unit in (:rating, :event))) ? (:psis_loo,) : criteria
    !isempty(eff_criteria) && allunique(eff_criteria) && all(in((:waic, :psis_loo)), eff_criteria) ||
        throw(ArgumentError("StanAdapter criteria supports distinct entries from (:waic, :psis_loo)"))
    scores = map(eff_criteria) do c
        c === :waic ? waic_report(f) : psis_loo_report(f; pareto_k_threshold)
    end
    return (;
        schema = "bayesianmgmfrm.stan_adapter_criteria.v1",
        unit = meta.unit,
        dataset_id = meta.dataset_id,
        observation_binding = meta.observation_binding,
        observation_ids = copy(meta.observation_ids),
        scores = NamedTuple{eff_criteria}(scores),
        qualification = qualify(f),
        source_content_hash = r.content_hash,
    )
end

function compare_models(pairs_vec::AbstractVector{<:Pair}; criterion::Symbol = :psis_loo, pareto_k_threshold::Real = 0.7)
    criterion in (:psis_loo, :loo, :waic) ||
        throw(ArgumentError("StanAdapter compare_models requires criterion in (:psis_loo, :loo, :waic); got $(repr(criterion))"))
    length(pairs_vec) >= 2 || throw(ArgumentError("supply at least two labeled StanAdapter.Fit models to compare_models"))
    labels = [strip(string(first(p))) for p in pairs_vec]
    all(!isempty, labels) && allunique(labels) || throw(ArgumentError("distinct non-empty model labels are required"))
    fits = Fit[]
    for p in pairs_vec
        last(p) isa Fit || throw(ArgumentError("all compared models in StanAdapter.compare_models must be StanAdapter.Fit objects"))
        checked(last(p))
        push!(fits, last(p))
    end
    crit_key = criterion === :loo ? :psis_loo : criterion
    evals = [crit_key === :waic ? waic_report(fk) : psis_loo_report(fk; pareto_k_threshold) for fk in fits]
    meta0 = fits[1].record.log_lik_meta
    for (lbl, fk) in zip(labels, fits)
        m = fk.record.log_lik_meta
        m.unit === meta0.unit && m.observation_binding == meta0.observation_binding ||
            throw(ArgumentError("model $(repr(lbl)) does not bind the exact same $(meta0.unit) observations (`observation_binding` mismatch)"))
    end

    elpds = [crit_key === :waic ? e.elpd_waic : e.elpd_loo for e in evals]
    pws = [crit_key === :waic ? e.pointwise.elpd_waic : e.pointwise.elpd_loo for e in evals]
    order = sortperm(elpds; rev = true)
    best_idx = order[1]
    N_u = length(pws[best_idx])

    rows = [
        begin
            diff_vec = pws[idx] .- pws[best_idx]
            d_elpd = sum(diff_vec)
            se_d = (idx == best_idx || N_u <= 1) ? 0.0 : sqrt(N_u * var(diff_vec; corrected = true))
            (;
                rank = rnk,
                model_label = labels[idx],
                elpd = elpds[idx],
                p_effective = crit_key === :waic ? evals[idx].p_waic : evals[idx].p_loo,
                elpd_difference = d_elpd,
                se_difference = se_d,
                bad_pareto_k_count = crit_key === :waic ? missing : evals[idx].bad_pareto_k_count,
                max_pareto_k = crit_key === :waic ? missing : evals[idx].max_pareto_k,
                qualified = qualify(fits[idx]).qualified,
                source_content_hash = fits[idx].record.content_hash,
            )
        end for (rnk, idx) in enumerate(order)
    ]
    body = (;
        schema = COMPARISON_SCHEMA,
        criterion = crit_key,
        unit = meta0.unit,
        observation_binding = meta0.observation_binding,
        n_units = N_u,
        rows,
        warning = "Pointwise SE treats declared $(meta0.unit) units as i.i.d.; inspect pareto_k and whole-fit qualification before substantive selection.",
    )
    return merge(body, (; report_hash = B._cache_hash(body)))
end

function prior_sensitivity(f::Fit, alt;
        parameters = nothing,
        interval::Real = 0.95,
        pareto_k_threshold::Real = 0.7)
    r = checked(f)
    r.log_prior !== nothing ||
        throw(ArgumentError("prior_sensitivity requires an explicit `log_prior = \"...\"` column declared in StanAdapter `roles`"))
    lo, hi = B._interval_probabilities(Float64(interval))
    S = r.run.total_draws
    n_ch = r.run.controls.chains

    alt_label, alt_lp = if alt isa Symbol || alt isa AbstractString
        k = Symbol(alt)
        haskey(r.alt_log_priors, k) ||
            throw(ArgumentError("unknown alt_log_priors key $(repr(k)); available: $(keys(r.alt_log_priors))"))
        (String(k), r.alt_log_priors[k])
    elseif alt isa Pair && last(alt) isa AbstractVector{<:Real}
        v = Float64.(last(alt))
        length(v) == S && all(isfinite, v) || throw(ArgumentError("supplied alt log-prior vector must have $S finite elements"))
        (String(first(alt)), v)
    elseif alt isa AbstractVector{<:Real}
        v = Float64.(alt)
        length(v) == S && all(isfinite, v) || throw(ArgumentError("supplied alt log-prior vector must have $S finite elements"))
        ("alternative", v)
    elseif alt isa Function
        v = [Float64(alt(NamedTuple{Tuple(Symbol.(r.stan_columns))}(Tuple(r.run.draws[s, 1:length(r.stan_columns)])))) for s in 1:S]
        all(isfinite, v) || throw(ArgumentError("alt log-prior function returned non-finite values"))
        ("custom_function", v)
    else
        throw(ArgumentError("supply a key from `roles.alt_log_priors`, a `label => log_prior_vector` Pair, a Vector{Float64}, or a draw log-prior function"))
    end

    log_ratios = alt_lp .- r.log_prior
    if maximum(log_ratios) - minimum(log_ratios) <= 1e-14
        reff = 1.0
        ps = (; norm_log_weights = fill(-log(Float64(S)), S), pareto_k = 0.0, n_eff = Float64(S))
        w = fill(1.0 / S, S)
        k_ok = true
    else
        # Chain-aware relative efficiency for importance ratios
        reff = if n_ch >= 2 && div(S, n_ch) >= 4
            arr = reshape(exp.(log_ratios .- maximum(log_ratios)), div(S, n_ch), n_ch)
            e = Float64(B.MCMCDiagnosticTools.ess(arr; kind = :basic, split_chains = size(arr, 1) >= 8 ? 2 : 1)) / S
            (isfinite(e) && e > 0.0) ? e : 1.0
        else
            1.0
        end
        ps = B._SA_MOD._psis_smooth_log_ratios(log_ratios; r_eff = reff)
        w = exp.(ps.norm_log_weights)
        w ./= sum(w)
        k_ok = isfinite(ps.pareto_k) && ps.pareto_k <= Float64(pareto_k_threshold)
    end

    sel = _select_columns(r; parameters)
    rows = map(eachindex(sel.names)) do j
        vals = view(sel.values, :, j)
        base_m = mean(vals)
        base_sd = std(vals)
        sh_m = sum(w .* vals)
        sh_var = max(sum(w .* ((vals .- sh_m) .^ 2)), 0.0)
        sh_sd = sqrt(sh_var)
        ord = sortperm(vals)
        cw = cumsum(w[ord])
        q_at(p) = vals[ord[clamp(searchsortedfirst(cw, p), 1, length(vals))]]
        (;
            parameter = sel.names[j],
            block = sel.blocks[j],
            baseline_mean = base_m,
            baseline_sd = base_sd,
            baseline_lower = quantile(vals, lo),
            baseline_upper = quantile(vals, hi),
            shifted_mean = sh_m,
            shifted_sd = sh_sd,
            shifted_lower = q_at(lo),
            shifted_upper = q_at(hi),
            mean_shift = sh_m - base_m,
            standardized_shift = base_sd > 0 ? (sh_m - base_m) / base_sd : 0.0,
        )
    end
    body = (;
        schema = PRIOR_SENSITIVITY_SCHEMA,
        alternative = alt_label,
        interval = Float64(interval),
        pareto_k = ps.pareto_k,
        pareto_k_threshold = Float64(pareto_k_threshold),
        effective_sample_size = ps.n_eff,
        r_eff = reff,
        status = k_ok ? :reliable : :unreliable_high_pareto_k,
        rows,
        source_content_hash = r.content_hash,
    )
    return merge(body, (; report_hash = B._cache_hash(body)))
end

function report(f::Fit; parameters = nothing, interval::Real = 0.95, include_draws::Bool = false)
    r = checked(f)
    post = summary(f; parameters, interval)
    qual = qualify(f)
    clean_num(x) = x isa AbstractFloat && !isfinite(x) ? string(x) : x
    sanitize_nt(nt::NamedTuple) = (; (k => clean_num(getproperty(nt, k)) for k in keys(nt))...)
    crit = r.log_lik === nothing ? nothing : criteria_report(f)
    traces = if include_draws
        sel = _select_columns(r; parameters)
        (; chain_ids = copy(r.run.chain_ids), iterations = copy(r.run.iterations),
           parameter_names = sel.names, values = [collect(view(sel.values, s, :)) for s in 1:size(sel.values, 1)])
    else
        nothing
    end
    body = (;
        schema = REPORT_SCHEMA,
        source_content_hash = r.content_hash,
        summary = sanitize_nt(r.summary),
        provenance = r.provenance,
        qualification = (;
            qualified = qual.qualified,
            parameter_gate_passed = qual.parameter_gate_passed,
            sampler_gate_passed = qual.sampler_gate_passed,
            telemetry_complete = qual.telemetry_complete,
            thresholds = qual.thresholds,
        ),
        posterior = post.rows,
        criteria = crit === nothing ? nothing : (; crit.unit, crit.observation_binding,
            psis_loo_elpd = haskey(crit.scores, :psis_loo) ? crit.scores.psis_loo.elpd_loo : missing,
            waic_elpd = haskey(crit.scores, :waic) ? crit.scores.waic.elpd_waic : missing),
        traces,
        warnings = copy(r.warnings),
        scientific_acceptance = false,
    )
    return merge(body, (; report_hash = B._cache_hash(body)))
end

function save_result(path::AbstractString, f::Fit)
    checked(f)
    (ispath(path) || islink(path)) && throw(ArgumentError("refusing to overwrite existing file: $path"))
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
    (ispath(path) || islink(path)) && throw(ArgumentError("refusing to overwrite existing report: $path"))
    B._SA_MOD._save_atomic_json(path, rep)
end

function check_loaded_report(parsed)
    hasproperty(parsed, :schema) && parsed.schema in (REPORT_SCHEMA, COMPARISON_SCHEMA, PRIOR_SENSITIVITY_SCHEMA) ||
        throw(ArgumentError("unknown StanAdapter report schema"))
    return parsed
end

end # module StanAdapter

# ---------------------------------------------------------------------------
# Versioned Portable Joint-Draw Handoff Schema (`PortableHandoff`)
# Preserves exact `chain × iteration × parameter` IEEE-754 Float64 draws,
# NUTS telemetry, optional `log_lik` & `log_prior`, prior/reference contract,
# and SHA-256 integrity across processes and Julia versions.
# ---------------------------------------------------------------------------

"""
    plausible_values(mmle_fit; n_imputations, seed)
    plausible_values(bayesian_fit)

For a grouped scalar MRCML fit, draw abilities on each person's conditional MMLE
quadrature grid, or extract every retained Bayesian model-scale draw with its
original chain, iteration and parameter vector. The MMLE calibration, regression
and group SDs stay fixed across imputations. Read the source qualification in
`result.record.qualification`. Use `PortableHandoff.pv_rows(result)` for a long
table iterator, `contrast(result; group, reference)` for group mean comparisons,
and `save_report` / `load_report` with a separate SHA-256 receipt.
"""
function plausible_values end

module PortableHandoff

import ..BayesianMGMFRM as B
import ..StanAdapter as SA_ADAPT
using JSON3
using SHA
using Statistics

const HANDOFF_SCHEMA = "bayesianmgmfrm.portable_joint_draws_handoff.v1"

struct Handoff
    record::NamedTuple
    fit::SA_ADAPT.Fit
end

function Base.show(io::IO, h::Handoff)
    r = h.record
    print(io, "BayesianMGMFRM.PortableHandoff.Handoff(source_family=", repr(r.source_family),
        ", chains=", r.n_chains, ", draws_per_chain=", r.draws_per_chain,
        ", parameters=", length(r.parameter_names), ", scale=", repr(r.scale), ")")
end

function _clean_stat_num(x)
    x === nothing || ismissing(x) ? nothing :
        x isa Bool ? x :
        x isa Integer ? Int(x) :
        x isa AbstractFloat ? (isfinite(x) ? Float64(x) : nothing) : nothing
end

function _pack_sampler_stats(stats, chain_ids::Vector{Int}, iterations::Vector{Int}, logdensities::Vector{Float64})
    S = length(chain_ids)
    has_full = length(stats) == S
    return [
        begin
            st = has_full ? stats[i] : NamedTuple()
            (;
                chain = chain_ids[i],
                iteration = iterations[i],
                acceptance_rate = something(_clean_stat_num(get(st, :acceptance_rate, nothing)), 0.9),
                step_size = something(_clean_stat_num(get(st, :step_size, nothing)), 0.05),
                tree_depth = something(_clean_stat_num(get(st, :tree_depth, nothing)), 1),
                n_steps = something(_clean_stat_num(get(st, :n_steps, nothing)), 1),
                numerical_error = Bool(coalesce(get(st, :numerical_error, false), false)),
                hamiltonian_energy = something(_clean_stat_num(get(st, :hamiltonian_energy, nothing)), -logdensities[i]),
                log_density = Float64(logdensities[i]),
            )
        end for i in 1:S
    ]
end

function _producer_metadata()
    return (;
        julia_version = string(VERSION),
        package_version = string(pkgversion(B)),
        advancedhmc_version = string(pkgversion(B.AdvancedHMC)),
        diagnostic_tools_version = string(pkgversion(B.MCMCDiagnosticTools)),
        os = string(Sys.KERNEL),
        arch = string(Sys.ARCH),
    )
end

function _draws_ieee754_sha256(
        schema::AbstractString,
        source_family::AbstractString,
        scale::AbstractString,
        parameter_names::AbstractVector{<:AbstractString},
        chain_ids::AbstractVector{<:Integer},
        iterations::AbstractVector{<:Integer},
        draws::AbstractMatrix{<:Real},
        fixed_parameters,
        qualified::Bool)
    io = IOBuffer()
    _wstr(s::AbstractString) = (write(io, codeunits(String(s))); write(io, UInt8(0)))
    _wstr("bayesianmgmfrm.draws_ieee754_sha256.v1")
    _wstr(schema)
    _wstr(source_family)
    _wstr(scale)
    S, P = size(draws)
    write(io, htol(Int32(S)))
    write(io, htol(Int32(P)))
    for j in 1:P
        _wstr(parameter_names[j])
    end
    for s in 1:S
        write(io, htol(Int32(chain_ids[s])))
    end
    for s in 1:S
        write(io, htol(Int32(iterations[s])))
    end
    for s in 1:S
        for j in 1:P
            v = Float64(draws[s, j])
            v == 0.0 && (v = 0.0)
            write(io, htol(v))
        end
    end
    write(io, htol(Int32(length(fixed_parameters))))
    for fp in fixed_parameters
        _wstr(String(fp.block))
        _wstr(String(fp.name))
        fv = Float64(fp.value)
        fv == 0.0 && (fv = 0.0)
        write(io, htol(fv))
    end
    write(io, UInt8(qualified ? 1 : 0))
    return bytes2hex(sha256(take!(io)))
end

const _BUNDLE_CONSTRAINT_KEYS = (
    "category_levels", "family", "identification", "location_mode", "scale_identification",
    "status", "step_owner", "threshold_owner", "thresholds",
)

function _handoff_bundle_sha256(
        draws_ieee754_sha256::AbstractString,
        ids,
        prior_and_reference,
        missing_audit)
    io = IOBuffer()
    _wstr(s::AbstractString) = (write(io, codeunits(String(s))); write(io, UInt8(0)))
    _wstr("bayesianmgmfrm.handoff_bundle_sha256.v1")
    _wstr(lowercase(String(draws_ieee754_sha256)))

    # 1) Canonical ids dictionary (sorted keys, ordered string labels)
    if ids === nothing || ids === missing
        write(io, htol(Int32(0)))
    else
        id_keys = sort!(String[String(k) for k in keys(ids)])
        write(io, htol(Int32(length(id_keys))))
        for ks in id_keys
            vals = ids isa NamedTuple ? getproperty(ids, Symbol(ks)) : ids[Symbol(ks)]
            _wstr(ks)
            vlist = String[string(v) for v in vals]
            write(io, htol(Int32(length(vlist))))
            for v in vlist
                _wstr(v)
            end
        end
    end

    # 2) Canonical effective constraint fields from prior_and_reference
    c_pairs = Tuple{String,String}[]
    if prior_and_reference !== nothing && !(prior_and_reference === missing)
        for ck in _BUNDLE_CONSTRAINT_KEYS
            sym = Symbol(ck)
            if hasproperty(prior_and_reference, sym)
                v = getproperty(prior_and_reference, sym)
                if ck == "category_levels" && v isa AbstractVector && !isempty(v)
                    all(x -> x isa Integer && !(x isa Bool), v) ||
                        throw(ArgumentError("prior_and_reference.category_levels must contain only integers"))
                    push!(c_pairs, (ck, join((string(Int(x)) for x in v), ",")))
                elseif v !== nothing && !(v === missing) && (v isa AbstractString || v isa Symbol || v isa Number || v isa Bool)
                    push!(c_pairs, (ck, string(v)))
                end
            end
        end
    end
    write(io, htol(Int32(length(c_pairs))))
    for (ck, cv) in c_pairs
        _wstr(ck)
        _wstr(cv)
    end

    # 3) Canonical missing_audit record
    if missing_audit === nothing || missing_audit === missing
        write(io, UInt8(0))
    else
        write(io, UInt8(1))
        write(io, htol(Int32(get(missing_audit, :n_input_rows, 0))))
        write(io, htol(Int32(get(missing_audit, :n_retained_rows, 0))))
        write(io, htol(Int32(get(missing_audit, :n_dropped_rows, 0))))
        drows = hasproperty(missing_audit, :dropped_rows) && missing_audit.dropped_rows !== nothing ?
            Int32[Int32(x) for x in missing_audit.dropped_rows] : Int32[]
        write(io, htol(Int32(length(drows))))
        for r in drows
            write(io, htol(r))
        end
        dbc = hasproperty(missing_audit, :dropped_by_column) ? missing_audit.dropped_by_column : nothing
        if dbc === nothing || dbc === missing
            write(io, htol(Int32(0)))
        else
            dbc_keys = sort!(String[String(k) for k in keys(dbc)])
            write(io, htol(Int32(length(dbc_keys))))
            for ks in dbc_keys
                cnt = dbc isa NamedTuple ? getproperty(dbc, Symbol(ks)) :
                      dbc isa AbstractDict ? (haskey(dbc, Symbol(ks)) ? dbc[Symbol(ks)] : dbc[ks]) :
                      dbc[Symbol(ks)]
                _wstr(ks)
                write(io, htol(Int32(cnt)))
            end
        end
    end
    return bytes2hex(sha256(take!(io)))
end

function _assemble_handoff(;
        source_family::String,
        source_schema::String,
        source_content_hash::String,
        scale::Symbol,
        chain_ids::Vector{Int},
        iterations::Vector{Int},
        parameter_names::Vector{String},
        parameter_blocks::Vector{Symbol},
        fixed_parameters::Vector{NamedTuple},
        draws::Matrix{Float64},
        logdensities::Vector{Float64},
        sampler_stats_raw,
        sampler_controls::NamedTuple,
        prior_and_reference,
        qualification_snapshot::NamedTuple,
        log_lik_payload = nothing,
        log_prior_vec = nothing,
        ids = nothing,
        missing_audit = nothing,
        prior_summary = nothing,
        warnings::Vector{String} = String[])
    S, P = size(draws)
    length(chain_ids) == S && length(iterations) == S && length(logdensities) == S ||
        throw(DimensionMismatch("handoff chain_ids, iterations, and logdensities must match size(draws, 1) = $S"))
    length(parameter_names) == P && length(parameter_blocks) == P ||
        throw(DimensionMismatch("handoff parameter_names and parameter_blocks must match size(draws, 2) = $P"))
    all(isfinite, draws) && all(isfinite, logdensities) ||
        throw(ArgumentError("portable handoff requires finite parameter draws and log-densities"))
    chains_u = sort(unique(chain_ids))
    n_chains = length(chains_u)
    chains_u == collect(1:n_chains) && S % n_chains == 0 ||
        throw(ArgumentError("portable handoff requires complete equal-length chains 1..$n_chains"))
    draws_per_chain = div(S, n_chains)
    chain_ids == repeat(1:n_chains; inner = draws_per_chain) &&
        iterations == repeat(1:draws_per_chain; outer = n_chains) ||
        throw(ArgumentError("portable handoff requires canonical chain-major (chain 1..C, iteration 1..S_c) ordering"))

    packed_stats = _pack_sampler_stats(sampler_stats_raw, chain_ids, iterations, logdensities)
    draw_rows = [Float64[draws[s, j] for j in 1:P] for s in 1:S]

    ll_block = if log_lik_payload === nothing
        nothing
    else
        ll_m = log_lik_payload.matrix
        size(ll_m, 1) == S || throw(DimensionMismatch("log_lik matrix rows must equal $S"))
        (;
            unit = String(log_lik_payload.unit),
            dataset_id = String(log_lik_payload.dataset_id),
            observation_binding = String(log_lik_payload.observation_binding),
            observation_ids = String[String(x) for x in log_lik_payload.observation_ids],
            rows = [Float64[ll_m[s, k] for k in 1:size(ll_m, 2)] for s in 1:S],
        )
    end
    lp_block = log_prior_vec === nothing ? nothing : Float64.(log_prior_vec)
    fixed_norm = [(; block = String(x.block), name = String(x.name), value = Float64(x.value)) for x in fixed_parameters]
    qual_json = JSON3.read(JSON3.write(B._json_export_value(qualification_snapshot)))

    ids_json = ids === nothing ? nothing : JSON3.read(JSON3.write(B._json_export_value(ids)))
    ma_json = missing_audit === nothing ? nothing : JSON3.read(JSON3.write(B._json_export_value(missing_audit)))
    ps_json = prior_summary === nothing ? nothing : JSON3.read(JSON3.write(B._json_export_value(prior_summary)))
    pr_json = JSON3.read(JSON3.write(B._json_export_value(prior_and_reference)))

    body = (;
        schema = HANDOFF_SCHEMA,
        source_family,
        source_schema,
        source_content_hash,
        producer = _producer_metadata(),
        scale = String(scale),
        n_chains,
        draws_per_chain,
        total_draws = S,
        n_parameters = P,
        chain_ids,
        iterations,
        parameter_names,
        parameter_blocks = String.(parameter_blocks),
        fixed_parameters = fixed_norm,
        draws = draw_rows,
        logdensities,
        sampler_stats = packed_stats,
        sampler_controls = JSON3.read(JSON3.write(B._json_export_value(sampler_controls))),
        prior_and_reference = pr_json,
        qualification = qual_json,
        log_lik = ll_block,
        log_prior = lp_block,
        warnings,
        (ids_json === nothing ? (;) : (; ids = ids_json))...,
        (ma_json === nothing ? (;) : (; missing_audit = ma_json))...,
        (ps_json === nothing ? (;) : (; prior_summary = ps_json))...,
    )
    handoff_hash = _canonical_handoff_digest(body)
    draws_ieee754_sha256 = _draws_ieee754_sha256(
        HANDOFF_SCHEMA, source_family, String(scale), parameter_names,
        chain_ids, iterations, draws, fixed_norm,
        Bool(get(qualification_snapshot, :qualified, false)))
    handoff_bundle_sha256 = _handoff_bundle_sha256(
        draws_ieee754_sha256, ids_json, pr_json, ma_json)
    full_rec = merge(body, (; handoff_hash, draws_ieee754_sha256, handoff_bundle_sha256))
    return Handoff(full_rec, _handoff_to_stan_fit(full_rec))
end

function _canonical_handoff_digest(rec)
    ll_canon = if rec.log_lik === nothing || rec.log_lik === missing
        nothing
    else
        llb = rec.log_lik
        (;
            unit = String(llb.unit),
            dataset_id = String(llb.dataset_id),
            observation_binding = String(llb.observation_binding),
            observation_ids = String[String(x) for x in llb.observation_ids],
            rows = Vector{Float64}[Float64[Float64(v) for v in r] for r in llb.rows],
        )
    end
    lp_canon = (rec.log_prior === nothing || rec.log_prior === missing) ? nothing :
        Float64[Float64(x) for x in rec.log_prior]
    stats_canon = NamedTuple[
        (;
            chain = Int(st.chain),
            iteration = Int(st.iteration),
            acceptance_rate = Float64(st.acceptance_rate),
            step_size = Float64(st.step_size),
            tree_depth = Int(st.tree_depth),
            n_steps = Int(st.n_steps),
            numerical_error = Bool(st.numerical_error),
            hamiltonian_energy = Float64(st.hamiltonian_energy),
            log_density = Float64(st.log_density),
        ) for st in rec.sampler_stats
    ]
    fixed_canon = NamedTuple[
        (; block = String(x.block), name = String(x.name), value = Float64(x.value))
        for x in rec.fixed_parameters
    ]
    ids_canon = if hasproperty(rec, :ids) && rec.ids !== nothing && !(rec.ids === missing)
        ks = sort!(String[String(k) for k in keys(rec.ids)])
        [(ks_i, String[string(v) for v in (rec.ids isa NamedTuple ? getproperty(rec.ids, Symbol(ks_i)) : rec.ids[Symbol(ks_i)])]) for ks_i in ks]
    else
        nothing
    end
    ma_canon = if hasproperty(rec, :missing_audit) && rec.missing_audit !== nothing && !(rec.missing_audit === missing)
        ma = rec.missing_audit
        dbc = hasproperty(ma, :dropped_by_column) && ma.dropped_by_column !== nothing ? ma.dropped_by_column : nothing
        dbc_c = dbc === nothing ? Tuple{String,Int}[] :
            [(ks_i, Int(dbc isa NamedTuple ? getproperty(dbc, Symbol(ks_i)) : dbc[Symbol(ks_i)])) for ks_i in sort!(String[String(k) for k in keys(dbc)])]
        (;
            n_input_rows = Int(get(ma, :n_input_rows, 0)),
            n_retained_rows = Int(get(ma, :n_retained_rows, 0)),
            n_dropped_rows = Int(get(ma, :n_dropped_rows, 0)),
            dropped_rows = hasproperty(ma, :dropped_rows) && ma.dropped_rows !== nothing ? Int[Int(x) for x in ma.dropped_rows] : Int[],
            dropped_by_column = dbc_c,
        )
    else
        nothing
    end
    return B._cache_hash((;
        schema = String(rec.schema),
        source_family = String(rec.source_family),
        source_schema = String(rec.source_schema),
        source_content_hash = String(rec.source_content_hash),
        scale = String(rec.scale),
        n_chains = Int(rec.n_chains),
        draws_per_chain = Int(rec.draws_per_chain),
        total_draws = Int(rec.total_draws),
        n_parameters = Int(rec.n_parameters),
        chain_ids = Int[Int(x) for x in rec.chain_ids],
        iterations = Int[Int(x) for x in rec.iterations],
        parameter_names = String[String(x) for x in rec.parameter_names],
        parameter_blocks = String[String(x) for x in rec.parameter_blocks],
        fixed_parameters = fixed_canon,
        draws = Vector{Float64}[Float64[Float64(v) for v in r] for r in rec.draws],
        logdensities = Float64[Float64(x) for x in rec.logdensities],
        sampler_stats = stats_canon,
        log_lik = ll_canon,
        log_prior = lp_canon,
        warnings = String[String(w) for w in rec.warnings],
        (ids_canon === nothing ? (;) : (; ids = ids_canon))...,
        (ma_canon === nothing ? (;) : (; missing_audit = ma_canon))...,
    ))
end

function _handoff_to_stan_fit(rec)
    S = Int(rec.total_draws)
    P = Int(rec.n_parameters)
    n_chains = Int(rec.n_chains)
    ndraws = Int(rec.draws_per_chain)
    pnames = String[String(x) for x in rec.parameter_names]
    pblocks = Symbol[Symbol(x) for x in rec.parameter_blocks]
    fixed_entries = NamedTuple[(; block = Symbol(x.block), name = String(x.name), value = Float64(x.value)) for x in rec.fixed_parameters]
    fixed_set = Set{String}([x.name for x in fixed_entries])
    free_cols = [nm for nm in pnames if !(nm in fixed_set)]

    draws = Matrix{Float64}(undef, S, P)
    for s in 1:S
        row = rec.draws[s]
        length(row) == P || throw(ArgumentError("corrupted handoff draw row $s"))
        for j in 1:P
            v = Float64(row[j])
            isfinite(v) || throw(ArgumentError("non-finite draw in portable handoff"))
            draws[s, j] = v
        end
    end
    chain_ids = Int[Int(x) for x in rec.chain_ids]
    iterations = Int[Int(x) for x in rec.iterations]
    logdensities = Float64[Float64(x) for x in rec.logdensities]

    sampler_stats = NamedTuple[
        (;
            chain = Int(st.chain),
            iteration = Int(st.iteration),
            acceptance_rate = Float64(st.acceptance_rate),
            step_size = Float64(st.step_size),
            tree_depth = Int(st.tree_depth),
            n_steps = Int(st.n_steps),
            numerical_error = Bool(st.numerical_error),
            hamiltonian_energy = Float64(st.hamiltonian_energy),
            hamiltonian_energy_error = NaN,
            is_adapt = false,
            max_hamiltonian_energy_error = NaN,
            log_density = Float64(st.log_density),
        ) for st in rec.sampler_stats
    ]
    chain_acc = [mean(st.acceptance_rate for st in sampler_stats if st.chain == c) for c in 1:n_chains]
    controls = (;
        backend = :portable_handoff,
        chains = n_chains,
        warmup = Int(get(rec.sampler_controls, :warmup, 0)),
        ndraws,
        seed = get(rec.sampler_controls, :seed, missing),
        step_size = Float64(mean(st.step_size for st in sampler_stats)),
        max_depth = Int(get(rec.sampler_controls, :max_depth, 10)),
        target_accept = get(rec.sampler_controls, :target_accept, missing),
    )
    sampler_rows = B._generalized_candidate_sampler_rows(
        logdensities, iterations, chain_acc, sampler_stats, controls, :portable_handoff)
    checked_th = B._check_diagnostic_thresholds(1.01, 400.0)

    ll_meta = nothing
    ll_mat = nothing
    if rec.log_lik !== nothing && !(rec.log_lik === missing)
        llb = rec.log_lik
        obs_ids = String[String(x) for x in llb.observation_ids]
        K_ll = length(obs_ids)
        ll_mat = Matrix{Float64}(undef, S, K_ll)
        for s in 1:S
            r_ll = llb.rows[s]
            for k in 1:K_ll
                ll_mat[s, k] = Float64(r_ll[k])
            end
        end
        ll_meta = (;
            columns = ["log_lik.$k" for k in 1:K_ll],
            unit = Symbol(llb.unit),
            dataset_id = String(llb.dataset_id),
            observation_ids = obs_ids,
            observation_binding = String(llb.observation_binding),
        )
    end
    lp_vec = (rec.log_prior === nothing || rec.log_prior === missing) ? nothing : Float64[Float64(x) for x in rec.log_prior]

    run_nt = (;
        backend = :portable_handoff,
        sampler = :nuts,
        controls,
        checked = checked_th,
        split_chains_requested = true,
        total_draws = S,
        nparams = P,
        chain_ids,
        iterations,
        chain_acceptance = chain_acc,
        draws,
        logdensities,
        sampler_stats,
        sampler_rows,
    )
    prov = (;
        source_kind = :portable_handoff,
        csv_basenames = String[],
        csv_sha256 = String[String(rec.handoff_hash)],
        stan_source_sha256 = String(rec.source_content_hash),
        data_json_sha256 = missing,
        executable_sha256 = missing,
        cmdstan_version = missing,
        seed = controls.seed,
        julia_version = String(rec.producer.julia_version),
        package_version = String(rec.producer.package_version),
        os = String(rec.producer.os),
        arch = String(rec.producer.arch),
        metadata = (; source_family = String(rec.source_family), source_schema = String(rec.source_schema), scale = String(rec.scale)),
    )
    summary_nt = (;
        n_chains,
        warmup = controls.warmup,
        draws_per_chain = ndraws,
        total_draws = S,
        n_parameters = P,
        n_free_parameters = length(free_cols),
        n_fixed_parameters = length(fixed_entries),
        has_log_lik = ll_mat !== nothing,
        log_lik_unit = ll_meta === nothing ? missing : ll_meta.unit,
        n_log_lik_units = ll_mat === nothing ? 0 : size(ll_mat, 2),
        has_log_prior = lp_vec !== nothing,
        alt_log_prior_keys = (),
    )
    body = (;
        schema = SA_ADAPT.FIT_SCHEMA,
        summary = summary_nt,
        parameter_names = pnames,
        stan_columns = free_cols,
        parameter_blocks = pblocks,
        fixed_parameters = fixed_entries,
        fixed_name_set = sort!(collect(fixed_set)),
        run = run_nt,
        log_lik_meta = ll_meta,
        log_lik = ll_mat,
        log_prior_column = lp_vec === nothing ? nothing : "log_prior",
        log_prior = lp_vec,
        alt_log_priors = NamedTuple(),
        provenance = prov,
        warnings = String[String(w) for w in rec.warnings],
    )
    digest = B._cache_hash((;
        schema = SA_ADAPT.FIT_SCHEMA,
        parameter_names = pnames,
        parameter_blocks = pblocks,
        fixed_parameters = fixed_entries,
        chain_ids,
        iterations,
        draws,
        logdensities,
        log_lik_meta = ll_meta,
        log_lik = ll_mat,
        log_prior = lp_vec,
        provenance_hashes = (;
            csv_hashes = prov.csv_sha256,
            stan_source_sha256 = prov.stan_source_sha256,
            data_json_sha256 = prov.data_json_sha256,
            executable_sha256 = prov.executable_sha256,
        ),
    ))
    return SA_ADAPT.Fit(merge(body, (; content_hash = digest)))
end

to_fit(h::Handoff) = h.fit

"""
    PortableHandoff.export_handoff(fit; scale = :model, include_log_lik = false, include_log_prior = false)

Export any fitted Bayesian model (`MFRMFit`/SupportedCommonFit, `AdditiveFacets.Fit`,
`StarResult`, sample record, `ConcurrentWorkflow.Fit`, or `StanAdapter.Fit`)
into a versioned, SHA-256-sealed portable joint-draw handoff (`"bayesianmgmfrm.portable_joint_draws_handoff.v1"`).
Save with `save_report(path, handoff; return_receipt = true)` and restore in any
process via `load_report(path; expected_sha256 = receipt.sha256)`.
"""
function export_handoff(f::SA_ADAPT.Fit; scale::Symbol = :model, include_log_lik::Bool = true, include_log_prior::Bool = true)
    scale in (:model, :raw) || throw(ArgumentError("scale must be :model or :raw"))
    r = SA_ADAPT.checked(f)
    q = SA_ADAPT.qualify(f)
    ll_p = (include_log_lik && r.log_lik !== nothing) ?
        (; unit = r.log_lik_meta.unit, dataset_id = r.log_lik_meta.dataset_id,
           observation_binding = r.log_lik_meta.observation_binding,
           observation_ids = r.log_lik_meta.observation_ids, matrix = r.log_lik) : nothing
    lp_v = (include_log_prior && r.log_prior !== nothing) ? r.log_prior : nothing
    return _assemble_handoff(;
        source_family = "stan_adapter",
        source_schema = r.schema,
        source_content_hash = r.content_hash,
        scale,
        chain_ids = copy(r.run.chain_ids),
        iterations = copy(r.run.iterations),
        parameter_names = copy(r.parameter_names),
        parameter_blocks = copy(r.parameter_blocks),
        fixed_parameters = copy(r.fixed_parameters),
        draws = copy(r.run.draws),
        logdensities = copy(r.run.logdensities),
        sampler_stats_raw = r.run.sampler_stats,
        sampler_controls = r.run.controls,
        prior_and_reference = r.provenance,
        qualification_snapshot = (; q.qualified, q.max_rhat, q.min_bulk_ess, q.min_tail_ess, q.n_divergences,
            q.parameter_gate_passed, q.sampler_gate_passed, q.telemetry_complete),
        log_lik_payload = ll_p,
        log_prior_vec = lp_v,
        warnings = copy(r.warnings))
end

function _common_fit_prior_summary(fit)
    hasproperty(fit, :prior) || return nothing
    p = fit.prior
    if fit isa B.MFRMFit
        return (;
            family = "reference_mfrm",
            coordinate_space = "identified_direct",
            person = (; role = "person_ability", family = "Normal",
                label = "Normal(0, $(round(p.person_sd; digits = 4)))", sd = p.person_sd),
            rater = (; role = "rater_severity", family = "Normal",
                label = "Normal(0, $(round(p.rater_sd; digits = 4)))", sd = p.rater_sd),
            item = (; role = "item_difficulty", family = "Normal",
                label = "Normal(0, $(round(p.item_sd; digits = 4)))", sd = p.item_sd),
            step = (; role = "category_step", family = "Normal",
                label = "Normal(0, $(round(p.step_sd; digits = 4)))", sd = p.step_sd),
        )
    elseif fit isa B.GMFRMFit
        return (;
            family = "gmfrm",
            coordinate_space = "raw_unconstrained",
            identification = "gmfrm_item_sum_to_zero",
            threshold_owner = "rater",
            estimator = "nuts_only",
            person = (; role = "person_ability", family = "Normal",
                label = "Normal(0, $(round(p.person_sd; digits = 4)))", sd = p.person_sd),
            rater = (; role = "rater_severity", family = "Normal",
                label = "Normal(0, $(round(p.rater_sd; digits = 4)))", sd = p.rater_sd),
            item = (; role = "item_free", family = "Normal",
                label = "Normal(0, $(round(p.item_sd; digits = 4)))", sd = p.item_sd),
            log_item_discrimination = (; role = "log_item_discrimination_free", family = "Normal",
                label = "Normal(0, $(round(p.log_discrimination_sd; digits = 4)))", sd = p.log_discrimination_sd),
            log_rater_consistency = (; role = "log_rater_consistency", family = "Normal",
                label = "Normal(0, $(round(p.log_consistency_sd; digits = 4)))", sd = p.log_consistency_sd),
            step = (; role = "rater_steps", family = "Normal",
                label = "Normal(0, $(round(p.step_sd; digits = 4)))", sd = p.step_sd),
        )
    elseif fit isa B.MGMFRMFit
        return (;
            family = "mgmfrm",
            coordinate_space = "raw_unconstrained",
            estimator = "nuts_only",
            person = (; role = "person_ability", family = "Normal",
                label = "Normal(0, $(round(p.person_sd; digits = 4)))", sd = p.person_sd),
            rater = (; role = "rater_severity", family = "Normal",
                label = "Normal(0, $(round(p.rater_sd; digits = 4)))", sd = p.rater_sd),
            item = (; role = "item_difficulty", family = "Normal",
                label = "Normal(0, $(round(p.item_sd; digits = 4)))", sd = p.item_sd),
            log_item_discrimination = (; role = "log_item_discrimination", family = "Normal",
                label = "Normal(0, $(round(p.log_discrimination_sd; digits = 4)))", sd = p.log_discrimination_sd),
            log_rater_consistency = (; role = "log_rater_consistency", family = "Normal",
                label = "Normal(0, $(round(p.log_consistency_sd; digits = 4)))", sd = p.log_consistency_sd),
            step = (; role = "item_steps", family = "Normal",
                label = "Normal(0, $(round(p.step_sd; digits = 4)))", sd = p.step_sd),
        )
    end
    return nothing
end

function export_handoff(fit::B._SupportedCommonFit; scale::Symbol = :model, include_log_lik::Bool = false, include_log_prior::Bool = false, ids = nothing)
    scale in (:model, :raw) || throw(ArgumentError("scale must be :model or :raw"))
    ctx = B._recovery_context(fit)
    run = fit isa B._ModelComparisonFit ? fit : fit.record.run
    q = B.qualify(fit)
    if scale === :model
        pnames = [c.parameter for c in ctx.coordinates]
        pblocks = [B._recovery_quantity(c, ctx.spec).block for c in ctx.coordinates]
        draws = hcat([Float64.(c.values) for c in ctx.coordinates]...)
        fixed = NamedTuple[(; block = B._recovery_quantity(c, ctx.spec).block, name = c.parameter, value = Float64(c.values[1]))
            for c in ctx.coordinates if c.fixed]
    else
        pnames = B.parameter_names(fit; scale = :raw)
        pblocks = fill(:raw, length(pnames))
        draws = Float64.(run.draws)
        fixed = NamedTuple[]
    end
    ll_p = if include_log_lik
        p_ctx = B.PredictionObservationAdapter._context(fit, nothing, nothing, B.Random.default_rng())
        _, ll_m = B.PredictionObservationAdapter._prediction_arrays(p_ctx.design, p_ctx.direct, false)
        obs_ids = ["obs_$i" for i in 1:size(ll_m, 2)]
        (; unit = :rating, dataset_id = "common_fit",
           observation_binding = B._cache_hash((; unit = :rating, n = size(ll_m, 2), scores = B.PredictionObservationAdapter._fit_data(fit).score)),
           observation_ids = obs_ids, matrix = ll_m)
    else
        nothing
    end
    lp_v = if include_log_prior && fit isa B.MFRMFit
        [B.logprior(fit.design, view(fit.draws, s, :), fit.prior) for s in 1:size(fit.draws, 1)]
    else
        nothing
    end
    lps = hasproperty(fit, :log_posterior) ? Float64.(fit.log_posterior) : Float64.(run.logdensities)
    src_hash = ctx.source_sample_hash === nothing ?
        B._cache_hash((; draws, lps, chain_ids = Int.(ctx.chain_ids), iterations = Int.(ctx.iterations))) :
        String(ctx.source_sample_hash)
    fd = ctx.spec.data
    ids_nt = ids !== nothing ? ids : merge(
        (; person = String.(string.(fd.person_levels)), item = String.(string.(fd.item_levels))),
        fd.columns.rater === nothing ? (;) : (; rater = String.(string.(fd.rater_levels))),
    )
    ma = hasproperty(fd.columns, :missing_audit) ? deepcopy(fd.columns.missing_audit) : nothing
    c_raw = B.contract(fit)
    eff_m = B._cr5_effective_model(ctx.spec)
    eff_id = (!isempty(ctx.spec.anchors) && ctx.spec.family === :mfrm) ? :hard_anchor : eff_m.identification
    eff_owner = eff_m.threshold_owner
    pr_common = merge(
        (; (k => getproperty(c_raw, k) for k in keys(c_raw) if k !== :identification)...),
        (;
            category_levels = Int.(fd.category_levels),
            n_categories = length(fd.category_levels),
            identification_declarations = hasproperty(c_raw, :identification) ? c_raw.identification : NamedTuple[],
            facet_identification = eff_id,
            identification = eff_id,
            threshold_owner = eff_owner,
            step_owner = eff_owner,
            population_location_mode = eff_m.location_mode,
        ),
    )
    return _assemble_handoff(;
        source_family = String(ctx.spec.family),
        source_schema = "bayesianmgmfrm.common_fit.v1",
        source_content_hash = src_hash,
        scale,
        chain_ids = Int.(ctx.chain_ids),
        iterations = Int.(ctx.iterations),
        parameter_names = pnames,
        parameter_blocks = pblocks,
        fixed_parameters = fixed,
        draws,
        logdensities = lps,
        sampler_stats_raw = run.sampler_stats,
        sampler_controls = B.sampler_controls(fit),
        prior_and_reference = pr_common,
        qualification_snapshot = (; q.qualified, q.max_rhat, q.min_bulk_ess, q.min_tail_ess, q.n_divergences),
        log_lik_payload = ll_p,
        log_prior_vec = lp_v,
        ids = ids_nt,
        missing_audit = ma,
        prior_summary = _common_fit_prior_summary(fit))
end

function export_handoff(f::B.AdditiveFacets.Fit; scale::Symbol = :model, include_log_lik::Bool = false, include_log_prior::Bool = false, ids = nothing)
    scale in (:model, :raw) || throw(ArgumentError("scale must be :model or :raw"))
    t = B.AdditiveFacets.checked(f; full = true)
    run = f.record.run
    q = B.qualify(f)
    if scale === :model
        m = B.AdditiveFacets.model_draws(t, run.draws)
        pnames = m.names
        draws = m.values
        pblocks = map(pnames) do nm
            startswith(nm, "person[") && return :person
            (startswith(nm, "step[") || startswith(nm, "steps[")) && return :thresholds
            (nm == "population_mean" || startswith(nm, "population[") || startswith(nm, "population_sd[")) && return :population
            startswith(nm, "residual_sd[") && return :hyperparameter
            for b in t.facets
                startswith(nm, "$(b.name)[") && return b.name
            end
            return :facet
        end
        fixed = NamedTuple[(; block = pblocks[i], name = nm, value = draws[1, i]) for (i, nm) in enumerate(pnames) if nm in m.fixed]
    else
        pnames = B.parameter_names(t; scale = :raw)
        draws = copy(run.draws)
        pblocks = fill(:raw, length(pnames))
        fixed = NamedTuple[]
    end
    ll_p = if include_log_lik && !(t isa Union{B.AdditiveFacets.ExplanatoryTarget, B.AdditiveFacets.MixedOutcomeTarget})
        S = size(run.draws, 1)
        pw1 = B.pointwise_loglikelihood(t, view(run.draws, 1, :))
        ll_m = Matrix{Float64}(undef, S, length(pw1))
        ll_m[1, :] .= pw1
        for s in 2:S
            ll_m[s, :] .= B.pointwise_loglikelihood(t, view(run.draws, s, :))
        end
        obs_ids = ["obs_$i" for i in 1:size(ll_m, 2)]
        (; unit = :rating, dataset_id = "additive_facets",
           observation_binding = f.record.target_identity,
           observation_ids = obs_ids, matrix = ll_m)
    else
        nothing
    end
    lp_v = include_log_prior ? [B.logprior(t, view(run.draws, s, :)) for s in 1:size(run.draws, 1)] : nothing
    id_pairs = Pair{Symbol,Vector{String}}[]
    hasproperty(t, :people) && push!(id_pairs, :person => String.(string.(t.people)))
    if hasproperty(t, :facets)
        for b in t.facets
            push!(id_pairs, b.name => String.(string.(b.levels)))
        end
    end
    ids_nt = ids !== nothing ? ids : (isempty(id_pairs) ? nothing : (; id_pairs...))
    ma = B._cr5_extract_missing_audit(t)
    c_add = B.contract(t)
    eff_owner = hasproperty(t, :owner) ? t.owner : (hasproperty(c_add, :step_owner) ? c_add.step_owner : :none)
    facet_id = if t isa B.AdditiveFacets.MRCMLTarget
        sr = t.spec_record
        if get(sr, :source, :custom_mrcml_spec) !== :structured_mfrm_spec || get(sr, :has_lltm, false)
            :mrcml_design_matrix
        elseif hasproperty(sr, :fixed_calibration)
            :isometric_fixed_calibration
        elseif hasproperty(sr, :calibration)
            :isometric_calibrated
        else
            :isometric
        end
    else
        :isometric
    end
    pop_loc_mode = hasproperty(c_add, :location_mode) ? c_add.location_mode :
        (hasproperty(t, :location_mode) ? t.location_mode : :additive_target)
    pr_add = merge(
        c_add,
        (;
            facet_identification = facet_id,
            identification = facet_id,
            threshold_owner = eff_owner,
            step_owner = eff_owner,
            population_location_mode = pop_loc_mode,
        ),
    )
    return _assemble_handoff(;
        source_family = "additive_facets",
        source_schema = f.record.schema,
        source_content_hash = f.record.content_hash,
        scale,
        chain_ids = copy(run.chain_ids),
        iterations = copy(run.iterations),
        parameter_names = pnames,
        parameter_blocks = pblocks,
        fixed_parameters = fixed,
        draws,
        logdensities = copy(run.logdensities),
        sampler_stats_raw = run.sampler_stats,
        sampler_controls = run.controls,
        prior_and_reference = pr_add,
        qualification_snapshot = (; q.qualified, q.max_rhat, q.min_bulk_ess, q.min_tail_ess, q.n_divergences,
            q.parameter_gate_passed, q.sampler_gate_passed, q.telemetry_complete),
        log_lik_payload = ll_p,
        log_prior_vec = lp_v,
        ids = ids_nt,
        missing_audit = ma,
        prior_summary = t isa B.AdditiveFacets.MRCMLTarget ? B.AdditiveFacets._mrcml_prior_summary(t) :
            t isa B.AdditiveFacets.ExplanatoryTarget ? deepcopy(t.specification) : nothing,
        warnings = copy(B.AdditiveFacets.design(t).warnings))
end

function export_handoff(res::B._SA_MOD.StarResult; scale::Symbol = :raw, include_log_lik::Bool = false, include_log_prior::Bool = false)
    scale === :raw || throw(ArgumentError("StarResult portable handoff exports unconstrained `:raw` coordinates (`reparameterize_draws` reconstructs substantive coordinates)"))
    m = res.model
    cfg = res.config
    S = size(res.draws, 1)
    n_chains = cfg.chains
    ndraws = cfg.ndraws
    chain_ids = repeat(1:n_chains; inner = ndraws)
    iterations = repeat(1:ndraws; outer = n_chains)
    pnames = B.parameter_names(m; scale = :raw)
    pblocks = [startswith(nm, "entity") ? :person : startswith(nm, "rater") ? :rater : :other for nm in pnames]
    lps = Float64.(res.logdensities)
    ll_p = if include_log_lik
        pw1 = B.pointwise_loglikelihood(m, view(res.draws, 1, :))
        ll_m = Matrix{Float64}(undef, S, length(pw1))
        ll_m[1, :] .= pw1
        for s in 2:S
            ll_m[s, :] .= B.pointwise_loglikelihood(m, view(res.draws, s, :))
        end
        (; unit = :event, dataset_id = "star_association",
           observation_binding = B._cache_hash((; events = m.event_ids, criteria = [String(c.id) for c in m.criteria])),
           observation_ids = copy(m.event_ids), matrix = ll_m)
    else
        nothing
    end
    lp_v = include_log_prior ? [B.logprior(m, view(res.draws, s, :)) for s in 1:S] : nothing
    q = B.qualify(res)
    return _assemble_handoff(;
        source_family = "star_association",
        source_schema = String(res.schema),
        source_content_hash = res.content_hash,
        scale = :raw,
        chain_ids,
        iterations,
        parameter_names = pnames,
        parameter_blocks = pblocks,
        fixed_parameters = NamedTuple[],
        draws = Float64.(res.draws),
        logdensities = lps,
        sampler_stats_raw = res.retained_stats,
        sampler_controls = B.sampler_controls(res),
        prior_and_reference = B.contract(m),
        qualification_snapshot = (; qualified = q.result.numerically_qualified),
        log_lik_payload = ll_p,
        log_prior_vec = lp_v,
        warnings = copy(res.warnings))
end

function export_handoff(r::NamedTuple; scale::Symbol = :raw, include_log_lik::Bool = false, include_log_prior::Bool = false)
    tag = B._sample_schema_symbol(r)
    tag !== nothing || throw(ArgumentError("unsupported NamedTuple record for PortableHandoff.export_handoff"))
    scale === :raw || throw(ArgumentError("sample records export `:raw` sampler coordinates in PortableHandoff"))
    t = B.getdesign(r)
    run = r.run
    pnames = B.parameter_names(t; scale = :raw)
    pblocks = fill(:raw, length(pnames))
    q = B.qualify(r)
    lp_v = include_log_prior ? [B.logprior(t, view(run.draws, s, :)) for s in 1:size(run.draws, 1)] : nothing
    return _assemble_handoff(;
        source_family = String(tag),
        source_schema = String(r.schema),
        source_content_hash = String(r.content_hash),
        scale = :raw,
        chain_ids = copy(run.chain_ids),
        iterations = copy(run.iterations),
        parameter_names = pnames,
        parameter_blocks = pblocks,
        fixed_parameters = NamedTuple[],
        draws = copy(run.draws),
        logdensities = copy(run.logdensities),
        sampler_stats_raw = run.sampler_stats,
        sampler_controls = run.controls,
        prior_and_reference = B.contract(t),
        qualification_snapshot = (; q.qualified, q.max_rhat, q.min_bulk_ess, q.min_tail_ess, q.n_divergences,
            q.parameter_gate_passed, q.sampler_gate_passed, q.telemetry_complete),
        log_lik_payload = nothing,
        log_prior_vec = lp_v)
end

function export_handoff(f::B._TI_MOD.ConcurrentWorkflow.Fit; scale::Symbol = :raw, include_log_lik::Bool = false, include_log_prior::Bool = false)
    scale === :raw || throw(ArgumentError("ConcurrentWorkflow.Fit portable handoff exports `:raw` sampler coordinates"))
    t = B._TI_MOD.ConcurrentWorkflow.checked(f; complete = true, full = false)
    n_chains = f.plan.record.controls.chains
    ndraws = f.plan.record.controls.ndraws
    S = n_chains * ndraws
    pnames = B.parameter_names(f; scale = :raw)
    pblocks = fill(:raw, length(pnames))
    draws = vcat([r.run.draws for r in f.chains]...)
    logdensities = vcat([r.run.logdensities for r in f.chains]...)
    chain_ids = repeat(1:n_chains; inner = ndraws)
    iterations = repeat(1:ndraws; outer = n_chains)
    stats_raw = NamedTuple[]
    for (ci, r) in enumerate(f.chains)
        for st in r.run.sampler_stats
            push!(stats_raw, merge(st, (; chain = ci)))
        end
    end
    q = B.qualify(f)
    ll_p = if include_log_lik
        pw1 = B.pointwise_loglikelihood(t, B._TI_MOD.ConcurrentWorkflow.native_point(f.plan, t, view(draws, 1, :)))
        ll_m = Matrix{Float64}(undef, S, length(pw1))
        ll_m[1, :] .= pw1
        for s in 2:S
            ll_m[s, :] .= B.pointwise_loglikelihood(t, B._TI_MOD.ConcurrentWorkflow.native_point(f.plan, t, view(draws, s, :)))
        end
        obs_ids = ["event_$i" for i in 1:size(ll_m, 2)]
        (; unit = :event, dataset_id = "concurrent_three_indicator",
           observation_binding = B._TI_MOD.ConcurrentWorkflow.identity(f),
           observation_ids = obs_ids, matrix = ll_m)
    else
        nothing
    end
    lp_v = include_log_prior ? [B.logprior(t, B._TI_MOD.ConcurrentWorkflow.native_point(f.plan, t, view(draws, s, :))) for s in 1:S] : nothing
    return _assemble_handoff(;
        source_family = "concurrent_three_indicator",
        source_schema = String(f.plan.record.schema),
        source_content_hash = B._TI_MOD.ConcurrentWorkflow.identity(f),
        scale = :raw,
        chain_ids,
        iterations,
        parameter_names = pnames,
        parameter_blocks = pblocks,
        fixed_parameters = NamedTuple[],
        draws,
        logdensities,
        sampler_stats_raw = stats_raw,
        sampler_controls = f.plan.record.controls,
        prior_and_reference = B.contract(t),
        qualification_snapshot = (; qualified = q.qualified),
        log_lik_payload = ll_p,
        log_prior_vec = lp_v)
end

function save_handoff(path::AbstractString, h::Handoff)
    (ispath(path) || islink(path)) && throw(ArgumentError("refusing to overwrite existing handoff file: $path"))
    B._SA_MOD._save_atomic_json(path, h.record)
end

function load_handoff(path::AbstractString)
    isfile(path) || throw(ArgumentError("portable handoff file not found: $path"))
    return load_handoff(B.JSON3.read(read(path, String)))
end

function load_handoff(parsed)
    hasproperty(parsed, :schema) && String(parsed.schema) == HANDOFF_SCHEMA ||
        throw(ArgumentError("invalid portable joint-draw handoff schema"))
    hasproperty(parsed, :handoff_hash) ||
        throw(ArgumentError("portable joint-draw handoff is missing handoff_hash"))
    String(parsed.handoff_hash) isa String && occursin(r"^[0-9a-f]{64}$", String(parsed.handoff_hash)) ||
        throw(ArgumentError("invalid handoff_hash format"))
    fit = _handoff_to_stan_fit(parsed)
    expected_hash = _canonical_handoff_digest(parsed)
    expected_hash == String(parsed.handoff_hash) ||
        throw(ArgumentError("portable handoff internal checksum mismatch"))
    actual_ieee_opt = nothing
    if hasproperty(parsed, :draws_ieee754_sha256) && parsed.draws_ieee754_sha256 !== nothing && !(parsed.draws_ieee754_sha256 === missing)
        stored_ieee = String(parsed.draws_ieee754_sha256)
        occursin(r"^[0-9a-f]{64}$", stored_ieee) ||
            throw(ArgumentError("invalid draws_ieee754_sha256 format"))
        fixed_norm = [(; block = String(x.block), name = String(x.name), value = Float64(x.value)) for x in parsed.fixed_parameters]
        q_flag = hasproperty(parsed, :qualification) && hasproperty(parsed.qualification, :qualified) ?
            Bool(parsed.qualification.qualified) : false
        actual_ieee = _draws_ieee754_sha256(
            String(parsed.schema), String(parsed.source_family), String(parsed.scale),
            String[String(x) for x in parsed.parameter_names],
            Int[Int(x) for x in parsed.chain_ids],
            Int[Int(x) for x in parsed.iterations],
            fit.record.run.draws, fixed_norm, q_flag)
        actual_ieee == stored_ieee ||
            throw(ArgumentError("portable handoff draws_ieee754_sha256 mismatch"))
        actual_ieee_opt = actual_ieee
    end
    if hasproperty(parsed, :handoff_bundle_sha256) && parsed.handoff_bundle_sha256 !== nothing && !(parsed.handoff_bundle_sha256 === missing)
        stored_bundle = String(parsed.handoff_bundle_sha256)
        occursin(r"^[0-9a-f]{64}$", stored_bundle) ||
            throw(ArgumentError("invalid handoff_bundle_sha256 format"))
        actual_ieee_opt !== nothing ||
            throw(ArgumentError("handoff_bundle_sha256 requires draws_ieee754_sha256"))
        ids_p = hasproperty(parsed, :ids) ? parsed.ids : nothing
        pr_p = hasproperty(parsed, :prior_and_reference) ? parsed.prior_and_reference : nothing
        ma_p = hasproperty(parsed, :missing_audit) ? parsed.missing_audit : nothing
        actual_bundle = _handoff_bundle_sha256(actual_ieee_opt, ids_p, pr_p, ma_p)
        actual_bundle == stored_bundle ||
            throw(ArgumentError("portable handoff handoff_bundle_sha256 mismatch (IDs, constraints, or missing_audit modified)"))
    end
    rec_nt = parsed isa NamedTuple ? parsed : (; (Symbol(k) => parsed[k] for k in keys(parsed))...)
    return Handoff(rec_nt, fit)
end

include("plausible_values.jl")

end # module PortableHandoff

contrast(pv::PortableHandoff.PlausibleValues; group, reference, level = 0.95) =
    PortableHandoff.group_contrast(pv; group, reference, level)

# ---------------------------------------------------------------------------
# Layer-1 & Layer-2 Root Dispatches for `StanAdapter.Fit` and `PortableHandoff.Handoff`
# ---------------------------------------------------------------------------

for _T_wrap in (:(StanAdapter.Fit), :(PortableHandoff.Handoff))
    _unwrap(ex) = _T_wrap == :(PortableHandoff.Handoff) ? :(PortableHandoff.to_fit($ex)) : ex
    @eval begin
        getdesign(f::$_T_wrap) = StanAdapter.checked($(_unwrap(:f)))
        design_summary(f::$_T_wrap) = (;
            schema = "bayesianmgmfrm.stan_adapter_design_summary.v1",
            StanAdapter.checked($(_unwrap(:f))).summary...,
            provenance = StanAdapter.checked($(_unwrap(:f))).provenance,
        )
        validate_design(f::$_T_wrap) = (;
            passed = true,
            identified = true,
            telemetry_complete = qualify($(_unwrap(:f))).telemetry_complete,
        )
        contract(f::$_T_wrap) = (;
            schema = "bayesianmgmfrm.stan_adapter_contract.v1",
            inference_paradigm = :bayesian_mcmc_explicit_role_stan_adapter,
            explicit_roles_required = true,
            arbitrary_stan_parser = false,
            implicit_variable_guessing = false,
            has_log_lik = StanAdapter.checked($(_unwrap(:f))).summary.has_log_lik,
            log_lik_unit = StanAdapter.checked($(_unwrap(:f))).summary.log_lik_unit,
            has_log_prior = StanAdapter.checked($(_unwrap(:f))).summary.has_log_prior,
            provenance = StanAdapter.checked($(_unwrap(:f))).provenance,
        )
        function parameter_names(f::$_T_wrap; scale::Symbol = :model)
            r = StanAdapter.checked($(_unwrap(:f)))
            scale === :model && return copy(r.parameter_names)
            scale === :raw && return copy(r.stan_columns)
            throw(ArgumentError("scale must be :model or :raw"))
        end
        sampler_controls(f::$_T_wrap) = deepcopy(StanAdapter.checked($(_unwrap(:f))).run.controls)
        diagnostics(f::$_T_wrap) = StanAdapter.diagnostics($(_unwrap(:f)))
        qualify(f::$_T_wrap; kwargs...) = StanAdapter.qualify($(_unwrap(:f)); kwargs...)
        posterior_summary(f::$_T_wrap; kwargs...) = StanAdapter.summary($(_unwrap(:f)); kwargs...)
        posterior_mcse(f::$_T_wrap; kwargs...) = StanAdapter.mcse($(_unwrap(:f)); kwargs...)
        fit_report(f::$_T_wrap; kwargs...) = StanAdapter.report($(_unwrap(:f)); kwargs...)
        facet_summary(f::$_T_wrap; kwargs...) = StanAdapter.facet_summary($(_unwrap(:f)); kwargs...)
        contrast(f::$_T_wrap; kwargs...) = StanAdapter.contrast($(_unwrap(:f)); kwargs...)
        posterior_contrast(f::$_T_wrap; kwargs...) = StanAdapter.contrast($(_unwrap(:f)); kwargs...)
        ranking(f::$_T_wrap; kwargs...) = StanAdapter.ranking($(_unwrap(:f)); kwargs...)
        posterior_ranking(f::$_T_wrap; kwargs...) = StanAdapter.ranking($(_unwrap(:f)); kwargs...)
        reliability(f::$_T_wrap; kwargs...) = StanAdapter.reliability($(_unwrap(:f)); kwargs...)
        posterior_reliability(f::$_T_wrap; kwargs...) = StanAdapter.reliability($(_unwrap(:f)); kwargs...)
        classification(f::$_T_wrap; kwargs...) = StanAdapter.classification($(_unwrap(:f)); kwargs...)
        posterior_classification(f::$_T_wrap; kwargs...) = StanAdapter.classification($(_unwrap(:f)); kwargs...)
        waic(f::$_T_wrap) = StanAdapter.waic_report($(_unwrap(:f)))
        psis_loo(f::$_T_wrap; kwargs...) = StanAdapter.psis_loo_report($(_unwrap(:f)); kwargs...)
        criteria(f::$_T_wrap; kwargs...) = StanAdapter.criteria_report($(_unwrap(:f)); kwargs...)
        prior_sensitivity(f::$_T_wrap, alt; kwargs...) = StanAdapter.prior_sensitivity($(_unwrap(:f)), alt; kwargs...)
        function pointwise_loglikelihood_matrix(f::$_T_wrap)
            r = StanAdapter.checked($(_unwrap(:f)))
            ll, _ = StanAdapter._require_log_lik(r, :pointwise_loglikelihood_matrix)
            return copy(ll)
        end
        function pointwise_loglikelihood(f::$_T_wrap)
            r = StanAdapter.checked($(_unwrap(:f)))
            ll, meta = StanAdapter._require_log_lik(r, :pointwise_loglikelihood)
            return (;
                log_density = copy(ll),
                unit = meta.unit,
                dataset_id = meta.dataset_id,
                observation_binding = meta.observation_binding,
                observation_ids = copy(meta.observation_ids),
            )
        end
        function logprior(f::$_T_wrap)
            r = StanAdapter.checked($(_unwrap(:f)))
            r.log_prior !== nothing ||
                throw(ArgumentError("logprior requires an explicit `log_prior = \"...\"` column declared in StanAdapter `roles`"))
            return copy(r.log_prior)
        end
        function logposterior(f::$_T_wrap)
            r = StanAdapter.checked($(_unwrap(:f)))
            return copy(r.run.logdensities)
        end
        function loglikelihood(f::$_T_wrap)
            r = StanAdapter.checked($(_unwrap(:f)))
            ll, _ = StanAdapter._require_log_lik(r, :loglikelihood)
            return vec(sum(ll; dims = 2))
        end
        function plot(f::$_T_wrap; kind::Symbol = :posterior, kwargs...)
            extension = Base.get_extension(@__MODULE__, :BayesianMGMFRMCairoMakieExt)
            extension === nothing && throw(ArgumentError("BayesianMGMFRM.plot requires CairoMakie; run `using CairoMakie`"))
            return extension.plot_stan_adapter($(_unwrap(:f)); kind, kwargs...)
        end
    end
end

for _T_wrap in (:(StanAdapter.Fit), :(PortableHandoff.Handoff)),
    _generative_fn in (:coordinates, :logdensity_and_gradient, :stan_data, :predictive_check, :posterior_predictive_check, :event_probabilities, :category_summary)
    @eval function $(_generative_fn)(f::$_T_wrap, args...; kwargs...)
        throw(ArgumentError(string(
            $(QuoteNode(_generative_fn)),
            " requires a generative Julia likelihood target, whereas ",
            $(string(_T_wrap)),
            " wraps external/portable posterior draws without parsing arbitrary `.stan` code; use posterior_summary, facet_summary, contrast, ranking, reliability, classification, waic, psis_loo, criteria, compare_models, or prior_sensitivity.",
        )))
    end
end

save_fit(path::AbstractString, f::StanAdapter.Fit) = StanAdapter.save_result(path, f)
save_fit(path::AbstractString, h::PortableHandoff.Handoff) = StanAdapter.save_result(path, h.fit)
compare_models(primary::Pair{<:Any, <:Union{StanAdapter.Fit, PortableHandoff.Handoff}},
               baseline::Pair{<:Any, <:Union{StanAdapter.Fit, PortableHandoff.Handoff}}; kwargs...) =
    compare_models([primary, baseline]; kwargs...)
