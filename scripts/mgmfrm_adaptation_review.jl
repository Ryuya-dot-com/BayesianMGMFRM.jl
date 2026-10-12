module MGMFRMAdaptationReview

include("mgmfrm_adaptation_record.jl")
const A = MGMFRMAdaptationRecord
const B = A.B
using LinearAlgebra, Statistics

json_value(x) = A.portable_integers(B._json_export_value(x))
readjson(path) = B.JSON3.read(read(path,String),Dict{String,Any})
require(ok, message) = ok || throw(ArgumentError(message))
same(actual, expected, label) = require(isequal(actual,json_value(expected)), "$label mismatch")

function checked_file(directory, reference)
    path = joinpath(directory,reference["path"])
    require(isfile(path) && A.digest(path)==reference["sha256"],
        "missing or changed file: $(reference["path"])")
    return path
end

# Preserve the distinction between unavailable telemetry and a recorded NaN/Inf.
function values_summary(rows, key)
    values = [r[key] for r in rows]
    require(all(x->x===nothing || x isa Real || x in ("NaN","Inf","-Inf"),values),
        "invalid numeric telemetry: $key")
    finite = Float64[x for x in values if x isa Real && isfinite(x)]
    missing_count = count(isnothing,values)
    return (; available=length(values)-missing_count, missing=missing_count,
        nonfinite=length(values)-missing_count-length(finite),
        minimum=isempty(finite) ? nothing : minimum(finite),
        maximum=isempty(finite) ? nothing : maximum(finite),
        mean=isempty(finite) ? nothing : mean(finite),
        first=isempty(values) ? nothing : first(values),
        last=isempty(values) ? nothing : last(values))
end

function window_summary(rows, max_depth, backend)
    return (; iterations=length(rows),
        first_iteration=isempty(rows) ? nothing : first(rows)["iteration"],
        last_iteration=isempty(rows) ? nothing : last(rows)["iteration"],
        numerical_errors=count(r->r["numerical_error"],rows),
        max_depth_hits=count(r->r["tree_depth"]>=max_depth,rows),
        step_size=values_summary(rows,"step_size"),
        acceptance_statistic=values_summary(rows,"acceptance_rate"),
        density_field=backend=="cmdstan" ? "stan_lp" : "log_density",
        density=values_summary(rows,backend=="cmdstan" ? "stan_lp" : "log_density"),
        energy_error=values_summary(rows,"hamiltonian_energy_error"))
end

function metric_diagonal(snapshot, metric, nparams)
    values = snapshot["inverse_mass_matrix"]
    if metric=="dense"
        require(length(values)==nparams && all(v->v isa AbstractVector && length(v)==nparams,values),
            "dense metric shape mismatch")
        matrix = reduce(vcat,permutedims.(Float64.(v) for v in values))
        require(all(isfinite,matrix) && isapprox(matrix,matrix';rtol=sqrt(eps(Float64))) &&
            isposdef(Symmetric(matrix,:L)), "invalid dense inverse mass matrix")
        return diag(matrix)
    end
    require(metric in ("diagonal","unit") && length(values)==nparams &&
        all(x->x isa Real && isfinite(x) && x>0,values), "invalid diagonal inverse mass matrix")
    require(metric!="unit" || all(isone,values), "nonidentity unit metric")
    return values
end

function check_chain(chain, record, fit, base, directory)
    c, controls = chain["chain"], record["controls"]
    w, n = controls["warmup"], controls["ndraws"]
    p = length(base.blueprint.parameter_names)
    require(chain["completed"]===true, "incomplete chain $c")
    rows, metrics = chain["rows"], chain["metrics"]
    require(length(rows)==w+n && !isempty(metrics), "incomplete chain rows or metrics")
    raw = chain["initial_raw"]
    require(length(raw)==p && all(x->x isa Real && isfinite(x),raw), "invalid raw initial state")
    initial = record["coordinates"]["sampling"]=="raw" ? raw :
        B._mgmfrm_location_from_raw(B._MGMFRMLocationLogDensity(base),Float64.(raw))
    require(length(chain["initial_sampling"])==p &&
        isapprox(Float64.(chain["initial_sampling"]),Float64.(initial);atol=1e-14,rtol=1e-14),
        "sampling/raw initial state mismatch")
    times = [m["after_iteration"] for m in metrics]
    require(all(t->t isa Integer && 0<=t<=w,times) && issorted(times) &&
        length(unique(times))==length(times), "invalid metric update times")
    for m in metrics
        metric_diagonal(m,controls["metric"],p)
    end
    ahmc = record["backend"]=="advancedhmc"
    ahmc && require(first(times)==0, "missing initial metric")
    for (i,r) in enumerate(rows)
        require(r["chain"]==c && r["iteration"]==i && r["is_adapt"]===(i<=w) &&
            r["phase"]==(i<=w ? "warmup" : "retained"), "chain/iteration/phase mismatch")
        require(r["numerical_error"] isa Bool && r["tree_depth"] isa Integer &&
            r["tree_depth"]>=0, "invalid numerical error or tree depth")
        if ahmc
            require(r["metric_used"]==findlast(t->t<i,times) &&
                r["metric_after"]==findlast(t->t<=i,times), "metric timing mismatch")
        end
    end
    kernel = chain["retained_kernel"]
    require(kernel["adapted"]===(w>0) && kernel["metric_id"]==length(metrics) &&
        kernel["step_size"] isa Real && isfinite(kernel["step_size"]) && kernel["step_size"]>0,
        "invalid retained kernel")
    retained = rows[w+1:end]
    require(all(r->r["step_size"]==kernel["step_size"] &&
        r["metric_used"]==r["metric_after"]==kernel["metric_id"],retained),
        "changing retained kernel")
    indices = findall(==(c),fit.chain_ids)
    require(length(indices)==n && fit.iterations[indices]==collect(1:n), "fit chain layout mismatch")
    for (i,index) in enumerate(indices)
        stat, row = fit.sampler_stats[index], retained[i]
        require(stat.chain==c && stat.iteration==i, "fit sampler row order mismatch")
        for key in keys(stat)
            key===:iteration && continue # Cache iterations restart after warmup.
            !ahmc && key in (:log_density,:nom_step_size) && continue
            same(row[string(key)],getproperty(stat,key),"retained $key")
        end
    end
    warmup_summary = B._fit_warmup_diagnostics(fit)[c]
    observed = window_summary(rows[1:w],controls["max_depth"],record["backend"])
    require(warmup_summary.observed_iterations===w &&
        warmup_summary.n_divergences===observed.numerical_errors &&
        warmup_summary.n_max_treedepth===observed.max_depth_hits &&
        warmup_summary.n_nonfinite_logdensity===observed.density.nonfinite &&
        observed.density.missing==0, "fit warmup summary mismatch")
    if !ahmc
        require(chain["warmup"]==w && chain["ndraws"]==n &&
            chain["metric"]==B._cmdstan_metric(Symbol(controls["metric"])),
            "native chain controls mismatch")
        csv = checked_file(directory,chain["csv"])
        metric_path = chain["metric_json"]===nothing ? "" : checked_file(directory,chain["metric_json"])
        native = A.cmdstan_record(csv,metric_path,p,c,n,w,chain["metric"])
        for key in keys(native)
            same(chain[string(key)],getproperty(native,key),"native $key")
        end
        initial_file = checked_file(directory,chain["initial_file"])
        same(readjson(initial_file)["beta"],raw,"native initial state")
        parsed = B._cmdstan_read_csv(csv,n;warmup=w)
        same(json_value(parsed.values[:,8:7+p]),fit.draws[indices,:],"native retained draws")
        same(chain["seed"],controls["rng"]["chain_seeds"][c],"chain seed")
        same(chain["executable_sha256"],controls["cmdstan_executable_sha256"],"executable identity")
    end
    return nothing
end

"""
    review(directory; tail_fraction=0.2)

Read a complete adaptation record and its trusted local fit cache, verify their
correspondence, and summarize warmup, its final fraction, and retained telemetry.
The final fraction is a descriptive window, not a backend adaptation stage or
a convergence criterion. No sampling, cache refresh or source rewriting occurs.
Historical source hashes are preserved as provenance, not compared with today's
checkout. Missing CmdStan metric history remains unavailable, never zero updates.
"""
function review(directory; tail_fraction::Real=0.2)
    require(isfinite(tail_fraction) && 0<tail_fraction<=1, "tail_fraction must be in (0, 1]")
    path = joinpath(directory,"adaptation.json")
    record = readjson(path)
    require(get(record,"schema",nothing)=="bayesianmgmfrm.adaptation_record.v1" &&
        get(record,"status",nothing)=="complete", "review requires a complete v1 adaptation record")
    require(record["backend"] in ("advancedhmc","cmdstan"), "unsupported backend")
    fit_path = checked_file(directory,record["fit_cache"])
    fit = B.load_fit_cache(fit_path) # Only trusted local Julia Serialization files.
    require(fit isa B.MGMFRMFit, "review requires MGMFRM")
    same(record["backend"],fit.backend,"backend")
    same(record["controls"],fit.sampler_controls,"sampler controls")
    same(record["data_signature"],string(fit.design.spec.validation.data_signature),"input identity")
    same(record["model"]["design_identity"],B.model_manifest(fit.design).design_identity,"design identity")
    same(record["prior"],B._prior_cache_record(fit.prior),"prior")
    base = B._mgmfrm_guarded_local_fit_logdensity(fit.design;prior=fit.prior)
    coordinates = get(fit.sampler_controls,:sampling_coordinates,:raw)
    same(record["coordinates"],A.coordinate_record(base,coordinates),"coordinates")
    controls, backend = record["controls"], record["backend"]
    w, n, count_chains = controls["warmup"], controls["ndraws"], controls["chains"]
    require(w>=0 && n>0 && count_chains>0 && controls["max_depth"]>0, "invalid sampler dimensions")
    require(length(record["chains"])==count_chains &&
        [c["chain"] for c in record["chains"]]==collect(1:count_chains) &&
        length(fit.sampler_stats)==length(fit.chain_ids)==n*count_chains, "chain count mismatch")
    if backend=="cmdstan"
        same(readjson(checked_file(directory,record["cmdstan_data"])),
            B._cmdstan_mgmfrm_data(base),"native input")
    end
    tail = ceil(Int,w*tail_fraction)
    chains = map(record["chains"]) do c
        check_chain(c,record,fit,base,directory)
        rows, metrics = c["rows"], c["metrics"]
        diagonal = metric_diagonal(last(metrics),controls["metric"],length(base.blueprint.parameter_names))
        history = backend=="advancedhmc"
        (;chain=c["chain"],
            warmup=window_summary(rows[1:w],controls["max_depth"],backend),
            late_warmup=window_summary(rows[w-tail+1:w],controls["max_depth"],backend),
            retained=window_summary(rows[w+1:end],controls["max_depth"],backend),
            retained_kernel=c["retained_kernel"],
            metric=(;type=controls["metric"],history=history ? "recorded" : "not_recorded",
                updates=history ? length(metrics)-1 : nothing,
                update_iterations=history ? [m["after_iteration"] for m in metrics[2:end]] : nothing,
                final_diagonal_minimum=minimum(diagonal),final_diagonal_maximum=maximum(diagonal)))
    end
    return (;schema="bayesianmgmfrm.adaptation_review.v1",integrity="checked",
        interpretation="Record correspondence and descriptive telemetry only; no convergence or calibration acceptance.",
        input=(;adaptation_path=abspath(path),adaptation_sha256=A.digest(path),fit_cache=record["fit_cache"]),
        backend, coordinates=record["coordinates"], controls,
        window=(;tail_fraction,tail_iterations=tail,selection="last ceil(warmup * tail_fraction) iterations"),
        unavailable=record["unavailable"],environment=record["environment"],chains)
end

end

if abspath(PROGRAM_FILE)==@__FILE__
    length(ARGS)==2 || error("usage: julia --project=. scripts/mgmfrm_adaptation_review.jl RECORD_DIRECTORY OUTPUT.json")
    ispath(ARGS[2]) && error("output already exists: $(ARGS[2])")
    result = MGMFRMAdaptationReview.review(ARGS[1])
    MGMFRMAdaptationReview.B._write_json_record(ARGS[2],result)
end
