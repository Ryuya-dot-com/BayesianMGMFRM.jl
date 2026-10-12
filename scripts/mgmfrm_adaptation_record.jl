module MGMFRMAdaptationRecord

import BayesianMGMFRM as B
using SHA, Dates, LinearAlgebra

digest(path) = bytes2hex(sha256(read(path)))
metric_values(metric) = metric isa B.AdvancedHMC.UnitEuclideanMetric ?
    ones(size(metric, 1)) : copy(metric.M⁻¹)

function coordinate_record(base, coordinates)
    names = copy(base.blueprint.parameter_names)
    n, D = length(base.design.spec.data.person_levels), base.design.spec.dimensions
    if coordinates === :orthogonal_person_mean_item_offset
        for p in 1:n, d in 1:D
            k = base.blueprint.blocks[:person][(p-1)*D+d]
            names[k] = p == 1 ? "scaled_person_mean[D$d]" : "person_contrast[$(p-1),D$d]"
        end
        for (i,k) in enumerate(base.blueprint.blocks[:item])
            names[k] = "item_offset[$i]"
        end
    end
    return (; sampling=coordinates, stored=:raw_unconstrained,
        initialization=:raw_unconstrained, sampling_names=names,
        raw_names=copy(base.blueprint.parameter_names),
        transform=coordinates === :raw ? nothing : (;
            person_reflector=copy(B._MGMFRMLocationLogDensity(base).reflector),
            scaled_mean="sqrt(n_persons) * mean(theta[:, dimension])",
            item_offset="b[item] - sum(a[item, dimension] * mean(theta[:, dimension]))",
            logabsdet=0.0))
end

function source_record()
    root = dirname(dirname(pathof(B)))
    files = [joinpath(dir, file) for (dir, _, files) in walkdir(joinpath(root, "src"))
        for file in files if endswith(file, ".jl") || endswith(file, ".stan")]
    append!(files, [joinpath(root, file) for file in
        ("Project.toml", "Manifest.toml", "Manifest-v$(VERSION.major).$(VERSION.minor).toml")
        if isfile(joinpath(root, file))])
    return (; julia=string(VERSION), advancedhmc=string(Base.pkgversion(B.AdvancedHMC)),
        forwarddiff=string(Base.pkgversion(B.ForwardDiff)),
        source_files_on_disk=Dict(relpath(file, root) => digest(file) for file in files),
        recorder_sha256=digest(@__FILE__))
end

# Store a copy only when the metric changes. Rows explicitly reference both the
# metric used by the transition and the metric AFTER that iteration's adaptation.
function observe!(record, event)
    chains = record[:chains]
    if event.phase === :sampling_start
        event.chain == length(chains)+1 || error("unexpected chain start")
        record[:controls] = event.controls
        push!(chains, Dict{Symbol,Any}(:chain=>event.chain, :completed=>false,
            :initial_raw=>copy(event.initial_raw), :initial_sampling=>copy(event.initial_sampling),
            :metrics=>[(; after_iteration=0, inverse_mass_matrix=metric_values(event.metric))],
            :rows=>NamedTuple[]))
    elseif event.phase === :transition
        chain = chains[event.chain]
        rows, metrics = chain[:rows], chain[:metrics]
        i, warmup = event.stat.iterations, record[:controls].warmup
        i == length(rows)+1 || error("missing or repeated sampler iteration")
        event.stat.is_adapt == (i <= warmup) || error("unexpected adaptation boundary")
        used = length(metrics)
        after = metric_values(event.stat.mass_matrix)
        isequal(after, last(metrics).inverse_mass_matrix) ||
            push!(metrics, (; after_iteration=i, inverse_mass_matrix=after))
        row = B._advancedhmc_stat_row(event.stat, event.chain, i)
        push!(rows, (; row..., phase=i <= warmup ? :warmup : :retained,
            metric_used=used, metric_after=length(metrics)))
    elseif event.phase === :sampling_end
        chain, controls = chains[event.chain], record[:controls]
        rows = chain[:rows]
        length(rows) == controls.warmup+controls.ndraws || error("incomplete chain")
        retained = rows[controls.warmup+1:end]
        metric_id = first(retained).metric_used
        all(r -> r.metric_used == r.metric_after == metric_id &&
            r.step_size == first(retained).step_size, retained) ||
            error("retained sampling changed metric or step size")
        chain[:retained_kernel] = (; metric_id, step_size=first(retained).step_size,
            adapted=controls.warmup > 0)
        chain[:completed] = true
    else
        error("unknown sampling observation phase")
    end
    return nothing
end

# JSON consumers may parse large integer identifiers/seeds as Float64. Preserve
# their decimal spelling instead of losing bits (including nested manifest IDs).
function portable_integers(value)
    value isa Integer && !( -(2^53-1) <= value <= 2^53-1) && return string(value)
    value isa AbstractDict && return Dict(k=>portable_integers(v) for (k,v) in value)
    value isa AbstractVector && return portable_integers.(value)
    return value
end

function write_record(directory, record)
    temporary = joinpath(directory, "adaptation.json.tmp")
    B._write_json_record(temporary, portable_integers(B._json_export_value(record)))
    mv(temporary, joinpath(directory, "adaptation.json"); force=true)
end

function cmdstan_record(csv_path, metric_path, nparams, chain, ndraws, warmup, metric)
    metric in ("diag_e","dense_e","unit_e") || throw(ArgumentError("unknown CmdStan metric"))
    count(line->strip(line)=="# Adaptation terminated",eachline(csv_path)) == 1 ||
        throw(ArgumentError("missing or duplicate CmdStan adaptation section"))
    parsed = B._cmdstan_read_csv(csv_path, ndraws; warmup)
    names = ["beta.$i" for i in 1:nparams]
    beta_columns = [B._cmdstan_required_column(parsed.header, name) for name in names]
    beta_columns == collect(8:(7+nparams)) ||
        throw(ArgumentError("CmdStan beta columns do not match the recorded metric order"))
    stat_names = ("lp__", "accept_stat__", "stepsize__", "treedepth__",
        "n_leapfrog__", "divergent__", "energy__")
    columns = Dict(name=>B._cmdstan_required_column(parsed.header,name) for name in stat_names)
    rows = NamedTuple[]
    values = warmup == 0 ? parsed.values : vcat(parsed.warmup_values, parsed.values)
    for i in axes(values,1)
        value(name) = values[i,columns[name]]
        divergent = B._cmdstan_integer_stat(value("divergent__"),"divergent__")
        divergent in (0,1) || throw(ArgumentError("invalid CmdStan divergence indicator"))
        depth = B._cmdstan_integer_stat(value("treedepth__"),"treedepth__")
        steps = B._cmdstan_integer_stat(value("n_leapfrog__"),"n_leapfrog__")
        depth >= 0 && steps >= 0 || throw(ArgumentError("negative CmdStan sampler count"))
        push!(rows,(;chain,iteration=i,phase=i<=warmup ? :warmup : :retained,
            is_adapt=i<=warmup,is_accept=missing,acceptance_rate=value("accept_stat__"),
            # Stan lp__ omits constants; do not label it the Julia-evaluated density.
            log_density=missing,stan_lp=value("lp__"),hamiltonian_energy=value("energy__"),
            hamiltonian_energy_error=missing,max_hamiltonian_energy_error=missing,
            n_steps=steps,tree_depth=depth,numerical_error=divergent==1,
            step_size=value("stepsize__"),nom_step_size=missing,
            metric_used=i<=warmup ? missing : 1,metric_after=i<=warmup ? missing : 1))
    end
    retained = rows[warmup+1:end]
    step_size = first(retained).step_size
    isfinite(step_size) && step_size > 0 && all(r->r.step_size==step_size,retained) ||
        throw(ArgumentError("invalid or changing retained CmdStan step size"))
    inverse_mass_matrix, source = if warmup > 0
        native = B.JSON3.read(read(metric_path,String))
        native.metric_type == metric || throw(ArgumentError("CmdStan metric type mismatch"))
        native.stepsize == step_size || throw(ArgumentError("CmdStan metric/CSV step size mismatch"))
        array = native.inv_metric
        if metric == "dense_e"
            length(array)==nparams && all(r->r isa AbstractVector && length(r)==nparams,array) ||
                throw(ArgumentError("CmdStan dense metric shape mismatch"))
            matrix = reduce(vcat,[permutedims(Float64.(collect(r))) for r in array])
            # Online covariance can differ across the diagonal by a few ulps.
            # Check with Float64's usual relative tolerance; preserve the ORIGINAL
            # entries rather than silently symmetrizing the recorded metric.
            all(isfinite,matrix) && isapprox(matrix,transpose(matrix);rtol=sqrt(eps(Float64))) &&
                isposdef(Symmetric(matrix,:L)) ||
                throw(ArgumentError("CmdStan dense metric is not finite symmetric positive definite"))
            (matrix,:cmdstan_metric_json)
        else
            length(array)==nparams && all(x->x isa Real && isfinite(x) && x>0,array) ||
                throw(ArgumentError("CmdStan diagonal metric is invalid"))
            metric != "unit_e" || all(isone,array) || throw(ArgumentError("invalid unit metric"))
            (Float64.(collect(array)),:cmdstan_metric_json)
        end
    else
        # This adapter never supplies metric_file; adaptation is disabled. The
        # identity is the command's initial metric, not an estimated metric.
        (metric == "dense_e" ? Matrix{Float64}(I,nparams,nparams) : ones(nparams),
            :unadapted_command_default_identity)
    end
    symmetry_error = metric == "dense_e" ? maximum(abs,inverse_mass_matrix-transpose(inverse_mass_matrix)) : 0.0
    return (;rows,metrics=[(;after_iteration=warmup,inverse_mass_matrix,source,symmetry_error)],
        retained_kernel=(;metric_id=1,step_size,adapted=warmup>0),stan_parameter_names=names,
        metric_history=:not_recorded)
end

function archive_file(directory, path, name)
    destination = joinpath(directory,name)
    cp(path,destination;force=false)
    return (;path=name,sha256=digest(destination))
end

function observe_cmdstan!(record, directory, event)
    chains = record[:chains]
    if event.phase === :sampling_start
        event.chain == length(chains)+1 || error("unexpected CmdStan chain start")
        event.warmup == 0 || event.record_warmup || error("CmdStan warmup rows must be saved")
        if isempty(chains)
            record[:cmdstan_data] = archive_file(directory,event.data_path,"data.json")
        else
            digest(event.data_path) == record[:cmdstan_data].sha256 || error("CmdStan input changed")
        end
        push!(chains,Dict{Symbol,Any}(:chain=>event.chain,:completed=>false,
            :initial_raw=>copy(event.initial_raw),:initial_sampling=>copy(event.initial_raw),
            :seed=>event.seed,:command=>copy(event.command),
            :executable_sha256=>event.executable_sha256,
            :initial_file=>archive_file(directory,event.init_path,"init-$(event.chain).json"),
            :warmup=>event.warmup,:ndraws=>event.ndraws,:metric=>event.metric))
    elseif event.phase === :sampling_output
        chain = chains[event.chain]
        for (key,path,name) in ((:csv,event.output_path,"chain-$(event.chain).csv"),
                (:metric_json,event.metric_path,"chain-$(event.chain)_metric.json"))
            chain[key] = isfile(path) ? archive_file(directory,path,name) : nothing
        end
    elseif event.phase === :sampling_end
        chain = chains[event.chain]
        result = cmdstan_record(joinpath(directory,chain[:csv].path),
            chain[:metric_json] === nothing ? "" : joinpath(directory,chain[:metric_json].path),
            length(chain[:initial_raw]),event.chain,chain[:ndraws],chain[:warmup],chain[:metric])
        merge!(chain,Dict(pairs(result)))
        chain[:completed] = true
    else
        error("unknown CmdStan observation phase")
    end
    write_record(directory,record)
    return nothing
end

"""
    fit_recorded(directory, spec; prior=nothing, init=nothing,
        backend=:advancedhmc, sampling_coordinates=:raw, kwargs...)

Fit an independent fixed-Q MGMFRM and save its ordinary `fit.jls` plus a separate
`adaptation.json` in a NEW directory. Return the ordinary fit. This opt-in research
helper uses the existing sampler; it does not change the package cache schema.
All transition statistics, actual jittered starts, changed inverse mass matrices,
coordinate order, model/prior/input identity, controls and source hashes are saved.
Metrics are copied; `metric_used` precedes adaptation and `metric_after` follows it.

Caught errors leave a failed record with the observations received so far and are
re-thrown. A process kill can leave only the initial `started` record. Neither is a
complete fit. AdvancedHMC warmup positions, NUTS trees and RNG checkpoints are not recorded.
Existing directories are never reused. CmdStan supports raw coordinates and saves
native CSV (including warmup positions), data/init JSON and final metric JSON.
It does not expose warmup metric history; those row references remain missing.
Adapted metric recording requires CmdStan >= 2.34. Correlated models are unsupported.
"""
function fit_recorded(directory, spec::B.FacetSpec; prior=nothing, init=nothing,
        backend::Symbol=:advancedhmc, sampling_coordinates::Symbol=:raw, kwargs...)
    backend in (:advancedhmc,:cmdstan) || throw(ArgumentError("unsupported recording backend"))
    spec.family === :mgmfrm || throw(ArgumentError("adaptation recording requires MGMFRM"))
    B._check_guarded_mgmfrm_spec(spec)
    B._check_mgmfrm_sampling_coordinates(spec, sampling_coordinates, backend, true)
    any(k -> startswith(string(k), "_") || k === :record_warmup, keys(kwargs)) &&
        throw(ArgumentError("private sampler overrides are not supported by the recorder"))
    base = B._mgmfrm_guarded_local_fit_logdensity(spec; prior=B._guarded_mgmfrm_prior(prior))
    record = Dict{Symbol,Any}(
        :schema=>"bayesianmgmfrm.adaptation_record.v1", :status=>:started,
        :started_utc=>string(now(UTC)), :backend=>backend,
        :coordinates=>coordinate_record(base, sampling_coordinates),
        :model=>B.model_manifest(base.design), :data_signature=>string(spec.validation.data_signature),
        :prior=>B._prior_cache_record(base.prior), :environment=>source_record(),
        :requested_options=>Dict(k=>v for (k,v) in kwargs if k !== :rng),
        :supplied_initial_raw=>init === nothing ? nothing : copy(init),
        :controls=>nothing, :chains=>Dict{Symbol,Any}[],
        :integer_encoding=>"integers outside the exact JSON/Float64 range are decimal strings",
        :metric_timing=>backend === :advancedhmc ?
            "step_size belongs to this transition; metric_after follows its adaptation and is used by the next transition" :
            "warmup metric history is unavailable; only retained rows reference the final metric",
        :unavailable=>backend === :advancedhmc ?
            (:warmup_positions,:nuts_tree_states,:rng_checkpoints) :
            (:warmup_metric_history,:energy_errors,:nuts_tree_states,:rng_checkpoints))
    mkdir(directory) # Atomic refusal to overwrite any existing attempt.
    write_record(directory, record)
    try
        observer = backend === :advancedhmc ? event -> observe!(record,event) :
            event -> observe_cmdstan!(record,directory,event)
        # Keep opt-in CmdStan compilation outputs inside this new attempt unless
        # the caller explicitly selects another fresh build directory.
        options = backend === :cmdstan && get(kwargs,:cmdstan_cache_dir,nothing) === nothing ?
            merge((;kwargs...),(;cmdstan_cache_dir=joinpath(directory,"compile"))) : (;kwargs...)
        fitted = B.Experimental.fit(spec; prior, init, backend, sampling_coordinates,
            options..., _sampling_observer=observer)
        length(record[:chains]) == fitted.sampler_controls.chains &&
            all(c -> c[:completed], record[:chains]) || error("incomplete sampling record")
        record[:controls] = fitted.sampler_controls
        cache = joinpath(directory, "fit.jls")
        B.save_fit_cache(cache, fitted)
        record[:fit_cache] = (; path="fit.jls", sha256=digest(cache))
        record[:status] = :complete
        write_record(directory, record)
        return fitted
    catch err
        record[:status] = :failed
        record[:error] = sprint(showerror, err)
        write_record(directory, record)
        rethrow()
    end
end

end
