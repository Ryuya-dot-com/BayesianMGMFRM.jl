"""
    BayesianMGMFRM.Experimental.RaterDrift

Experimental scalar RW1/static fitting and descriptive comparison. Use `model`,
`design_review`, `prepare`, `fit`, `load_fit`, `summarize`, `load_report`, `report`,
`trajectory`, `plot_trajectory`, `compare` and `save_report`. See `contract()` and the Rater
Drift guide for the numerical, interpretation and environment boundaries.
"""
module RaterDrift
import BayesianMGMFRM as B
using JSON3, SHA
include("rater_drift/target.jl")
const M = RaterDriftCandidate
const SOURCE_SCHEMA = "bayesianmgmfrm.rw1_bridge_report.v1"
const SAVED_SCHEMA = "bayesianmgmfrm.rw1_saved_report.v1"
const PRODUCERS = ("334a179bbb768791c3aece65d80a0136a19749e6ab1f6278cab599260259b710",
    "8540f49481bb198e558a17b8999fec3ad486dc187e49ec5d9c9b1cacad8a6747")
const TARGET_SOURCE = "8e25d5f825bab8ed378ba77ff531443002e2f2f0807b32256f48417c581bf5d7"
_digest(x) = bytes2hex(sha256(x))
_require(x, message) = x === true || throw(ArgumentError(message))
_finite(x) = x isa Real && !(x isa Bool) && isfinite(x)
_hash(x) = x isa AbstractString && occursin(r"\A[0-9a-f]{64}\z", x)
function _same(x, y)
    if x isa AbstractDict && y isa AbstractDict
        return Set(string.(keys(x))) == Set(string.(keys(y))) &&
            all(_same(x[k], y[k]) for k in keys(x))
    elseif x isa AbstractArray && y isa AbstractArray
        return size(x) == size(y) && all(_same(a,b) for (a,b) in zip(x,y))
    end
    isequal(x,y)
end

"""Return the exact experimental input, saved-report and interpretation boundary."""
contract() = (;status=:experimental, api_version=3, scientific_acceptance=false,
    fitting=true, native_chain_import=true, report_only=false, static_comparison=true,
    model=:scalar_rw1_rater_step_pcm, processes=(:rw1,:static), link_multiplier=1.7, threshold_owner=:rater,
    time_grid=:regular_full_grid, interval_method=:pointwise_equal_tailed,
    conditioning=:retrospective_existing_performances_and_judges,
    forecast=false, change_point=false, causal_effect=false, stable_api=false)

"""
    model(rows; categories, time_ticks, time_labels, time_unit,
          process=:rw1, innovation_log_sd_mean=nothing)

Check scalar rater-step PCM input on a full regular RW1 grid. Each row supplies
`event_id`, `performance`, `rater`, `time` (nonempty string IDs) and integer
`score` in `0:categories-1`. Declare all possible categories, including unused
ones. Omit missing ratings; zero is an observed category. Each scoring event
has its own ID. A repeated performance ID means the same performance/recording,
not merely the same contestant, task or judge. Repeated recordings can link years.

`time` matches a declared `time_labels` entry. Integer ticks advance by one
declared unit, retaining unrated bins. Unequal observation gaps are represented
by empty bins. `innovation_log_sd_mean` explicitly sets the mean of a Normal
prior with SD one on log innovation SD; it is not a recommended default.
Performance and initial severity have independent standard Normal priors.
Rater steps sum to zero with the normalized Gaussian free-coordinate prior.
The adjacent-category logit is `1.7*(ability - severity - rater_step)`.
For `process=:static`, each judge has one constant severity with a standard
Normal prior and no innovations. Omit `innovation_log_sd_mean` in that case.
The performance/step priors, categories, logit scale and observed rows agree
with RW1. Static changes are imposed zeros; severity levels remain uncertain.
This operation does not fit or establish identification; use `design_review`.
"""
function model(rows; categories, time_ticks, time_labels, time_unit, process=:rw1, innovation_log_sd_mean=nothing)
    _require(process in (:rw1,:static),"process must be :rw1 or :static")
    _require(process===:static ? innovation_log_sd_mean===nothing : _finite(innovation_log_sd_mean),
        "RW1 requires an explicit innovation prior; static has no innovation prior")
    rows = collect(rows)
    _require(!isempty(rows), "rating rows are required")
    _require(all(r->hasproperty(r,:score),rows), "each rating row requires a score")
    for row in rows, name in (:event_id,:performance,:rater,:time)
        _require(hasproperty(row,name) && getproperty(row,name) isa AbstractString &&
            !isempty(strip(getproperty(row,name))), "nonempty string $name required")
    end
    people = unique(String[r.performance for r in rows])
    raters = unique(String[r.rater for r in rows])
    times = M.labels(time_labels,length(time_ticks))
    _require(all(r->r.time in times,rows), "rating time is absent from the full grid")
    M.Target(;P=length(people),R=length(raters),K=categories,
        person=[findfirst(==(r.performance),people) for r in rows],
        rater=[findfirst(==(r.rater),raters) for r in rows],
        time=[findfirst(==(r.time),times) for r in rows],score=[r.score for r in rows],
        event=[r.event_id for r in rows],person_labels=people,rater_labels=raters,
        time_ticks,time_labels=times,time_unit,mu_sigma=process===:static ? 0. : innovation_log_sd_mean,
        static=process===:static,parameterization=process===:static ? :centered : :noncentered)
end

function _target(s)
    M.Target(;P=s.P,R=s.R,K=s.K,person=collect(s.person),rater=collect(s.rater),
        time=collect(s.time),score=collect(s.score),event=collect(s.event),
        person_labels=collect(s.person_labels),rater_labels=collect(s.rater_labels),
        time_ticks=collect(s.time_ticks),time_labels=collect(s.time_labels),
        time_unit=s.time_unit,mu_sigma=s.mu_sigma,parameterization=Symbol(s.parameterization),static=s.static)
end

"""
    design_review(model; reference, panel_weights=nothing)

Check likelihood identification of each judge's change from the named reference.
`linked` means an estimable contrast, not adequate information or precision.
`data_confounded` means the contrast is not identified by this rating allocation;
`process_only_endpoint` means at least one endpoint has no direct ratings.
Proper priors do not repair likelihood identification. This exact rank check is
intended for small allocations. Optional fixed nonnegative panel weights sum to
one; their contrast is checked directly, not inferred from individual statuses.
"""
function design_review(t::M.Target; reference, panel_weights=nothing)
    _require(reference isa AbstractString && reference in t.time_labels,"unknown reference time")
    ref=only(findall(==(reference),t.time_labels));d=M.design_review(t;reference=ref)
    panel=nothing
    if panel_weights !== nothing
        _require(length(panel_weights)==t.R && all(w->_finite(w) && w>=0,panel_weights) &&
            isapprox(sum(panel_weights),1.;atol=1e-12,rtol=0),"fixed panel weights must sum to one")
        panel=[_panel_status(t,panel_weights,j,ref,d) for j in eachindex(t.time_ticks)]
    end
    merge(d,(;panel_status=panel,interpretation="Likelihood identification only; no precision or statistical acceptance."))
end

function _panel_status(t,weights,j,ref,design)
    t.static && return "static_constraint"
    j==ref && return "reference"
    members=findall(>(0),weights)
    any(!design.rated[r,j] || !design.rated[r,ref] for r in members) && return "process_only_endpoint"
    all(design.status[r,j]=="linked" for r in members) && return "linked"
    # Non-estimable individual changes can cancel in an estimable panel contrast.
    T=length(t.time_ticks);b=t.P+t.R*T;ncols=b+t.R*(t.K-2)
    A=zeros(Int,length(t.score)*(t.K-1),ncols)
    for n in eachindex(t.score),k in 1:t.K-1
        row=(n-1)*(t.K-1)+k;r=t.rater[n]
        A[row,t.person[n]]=1;A[row,t.P+(t.time[n]-1)*t.R+r]=-1
        for h in 1:t.K-2
            A[row,b+(h-1)*t.R+r]=k==t.K-1 ? 1 : k==h ? -1 : 0
        end
    end
    c=zeros(Rational{BigInt},1,ncols)
    for r in members
        c[1,t.P+(j-1)*t.R+r]+=Rational{BigInt}(weights[r])
        c[1,t.P+(ref-1)*t.R+r]-=Rational{BigInt}(weights[r])
    end
    M.exact_rank(vcat(A,c))==design.rank ? "linked" : "data_confounded"
end

"""Immutable computed-report bytes; use `load_report` to check the separate checksum."""
struct SavedReport
    source_json::String
    source_sha256::String
    function SavedReport(source_json::String, source_sha256::String)
        _require(_hash(source_sha256) && _digest(source_json)==source_sha256,"source report checksum differs")
        _check_source(JSON3.read(source_json))
        new(source_json,source_sha256)
    end
end

_change_status(d,j,r,ref) = j==ref ? "reference" : r==0 ? d.panel_status[j] : d.status[r,j]

function _check_source(x)
    current_report=x.schema==RaterDriftBridge.SCHEMA
    previous_report=x.schema=="bayesianmgmfrm.rw1_package_report.v1"
    package_report=current_report || previous_report
    target_hash=RaterDriftRecords.digest(joinpath(@__DIR__,"rater_drift","target.jl"))
    producer_ok=if current_report
        # The retained pair differs only in the owner of Normal/cdf, not its target or report.
        (x.adapter_sha256,x.context.target_sha256) in (
            (RaterDriftRecords.digest(joinpath(@__DIR__,"rater_drift","bridge.jl")),target_hash),
            ("307a3450358926c4cfffcde4e55a6b9cd46c7726ccc599252af47a318e115159",
             "c465bf2709866edcb6168232eebd5197eb34c8bdf69fa0a04a39b476c6a0c604"))
    elseif previous_report
        x.adapter_sha256=="248032272f342366f79f371be61ffa423574b5118cf77843346d67607a3fffb9" &&
            x.context.target_sha256==target_hash
    else
        x.schema==SOURCE_SCHEMA && x.adapter_sha256 in PRODUCERS && x.context.target_sha256==TARGET_SOURCE
    end
    _require(producer_ok,"unsupported saved report producer or target")
    _require(_same(x.policy,JSON3.read(JSON3.write((;batch_sizes=[100,200,400,800],primary_batch=200,
        diagnostic_method="cdf_and_unrounded_normal_coordinate",root_cdf_tolerance=1e-10,
        comparison_flag_mcse=3.)))),"unsupported conditional-integration policy")
    o=x.original_report;t=_target(o.target)
    _require((!t.static || current_report) && x.kind==o.kind=="posterior" && x.posterior===true && o.posterior===true,
        "only supported posterior computed reports are supported")
    _require(x.statistical_acceptance===false && o.statistical_acceptance===false &&
        x.public_api===package_report && o.public_api===package_report && x.new_fits==0 && x.new_model_random_draws==0 &&
        o.forecast===false && o.causal_effect===false &&
        o.conditioning=="retrospective_existing_performances_and_judges" &&
        o.interval_method=="pointwise_equal_tailed", "unsupported report interpretation")
    _require(o.schema=="bayesianmgmfrm.rw1_chain_report.v1" &&
        _hash(x.plan_hash) && x.plan_hash==o.plan_hash && _same(x.context,o.context) &&
        _hash(x.original_report_hash) && _hash(x.content_hash) &&
        x.original_numerical_qualified===o.numerical_qualified,"original report identity differs")
    _require(_finite(o.interval_mass) && 0<o.interval_mass<1 && _finite(o.epsilon) && o.epsilon>0,
        "invalid saved interval or practical tolerance")
    _require(o.numerical_qualified===(o.parameter_passed && o.sampler_passed && o.precision_passed),
        "original qualification is inconsistent")
    d=design_review(t;reference=o.reference,panel_weights=collect(o.panel_weights))
    for key in (:rank,:coordinates,:rank_deficiency,:reference,:time_labels,:rater_labels,:rated,:status)
        _require(_same(o.design[key],B._json_export_value(getproperty(d,key))),"saved design differs: $key")
    end
    T=length(t.time_ticks);R=t.R;ref=only(findall(==(o.reference),t.time_labels))
    _require(length(x.trajectory)==length(o.trajectory)==T*(R+1),"incomplete trajectory")
    for (i,(row,raw)) in enumerate(zip(x.trajectory,o.trajectory))
        j=div(i-1,R+1)+1;r=mod(i-1,R+1)
        label=r==0 ? nothing : t.rater_labels[r]
        status=t.static ? "static_constraint" : _change_status(d,j,r,ref)
        fixed=t.static || t.time_labels[j]==o.reference
        for v in (row,raw)
            _require(v.rater==label && v.time==t.time_labels[j] && v.tick==t.time_ticks[j] &&
                v.scope==(r==0 ? "panel" : "judge") && v.structurally_fixed===fixed &&
                v.design_status==status,"trajectory identity/design differs")
        end
        if fixed
            _require(row.summary===nothing && raw.summary===nothing && row.estimator=="structural_zero",
                "reference change must be a structural zero")
        else
            _require(row.estimator in ("joint_draws","conditional_gaussian_bridge"),"unknown interval estimator")
            s=row.summary
            _require(all(_finite,(s.mean,s.median,s.lower,s.upper)) && s.lower<=s.median<=s.upper,
                "invalid saved interval")
            _require(s.precision.mean_mcse===nothing || (_finite(s.precision.mean_mcse) &&
                s.precision.mean_mcse>=0),"invalid saved mean MCSE")
            _require(length(s.precision.quantiles)==3,"three saved quantiles required")
            for (q,p,value) in zip(s.precision.quantiles,((1-o.interval_mass)/2,.5,(1+o.interval_mass)/2),
                    (s.lower,s.median,s.upper))
                _require(q.probability==p && (q.mcse===nothing || (_finite(q.mcse) && q.mcse>=0)),
                    "invalid quantile probability or MCSE")
                _require((row.estimator=="joint_draws" ? q.estimate : q.quantile)==value,
                    "interval and precision rows disagree")
            end
            if row.estimator=="conditional_gaussian_bridge"
                ref=only(findall(==(o.reference),t.time_labels))
                active=r==0 ? findall(>(0),collect(o.panel_weights)) : [r]
                _require(1<j<T && all(a->!d.rated[a,j] && d.rated[a,j-1] &&
                    d.rated[a,j+1] && d.rated[a,ref],active),"unsupported conditional-integration bin")
            end
        end
        if row.estimator!="conditional_gaussian_bridge"
            _require(all(_same(row[k],raw[k]) for k in keys(raw)),"original joint-draw result changed")
        end
    end
    _require(count(r->r.estimator=="conditional_gaussian_bridge",x.trajectory)==x.count_integrated,
        "integrated row count differs")
    n=length(o.iterations)÷4
    _require(n>=10 && collect(o.chain_ids)==repeat(1:4;inner=n) &&
        collect(o.iterations)==repeat(1:n;outer=4) && length(o.chain_hashes)==4 && all(_hash,o.chain_hashes),
        "chain order or retained iteration identity differs")
    focal=filter(r->!r.structurally_fixed,x.trajectory)
    _require(x.precision_passed===all(r->r.precision_passed===true,focal) &&
        x.diagnostic_passed===all(r->r.diagnostic_passed===true,focal) &&
        x.numerical_qualified===(o.parameter_passed && o.sampler_passed && x.precision_passed && x.diagnostic_passed),
        "numerical qualification is inconsistent")
    current_report && _check_locations(x,t)
    x
end

"""
    load_report(path; expected_sha256)

Read an explicitly supported RW1 computed JSON report or a `save_report` copy.
Keep the SHA-256 receipt separately. The checksum detects changed bytes; it does
not authenticate an untrusted producer or establish statistical validity.
The original target, environment, diagnostics and warnings are retained. This
reads calculated values without loading native draws, re-estimating a model,
changing the reference/interval/prior, or claiming native cache compatibility.
"""
function load_report(path::AbstractString; expected_sha256)
    _require(_hash(expected_sha256),"separately retained SHA-256 required")
    bytes=read(path);_require(_digest(bytes)==expected_sha256,"saved file checksum differs")
    text=String(bytes);x=JSON3.read(text)
    if x.schema==COMPARISON_SCHEMA
        return SavedComparison(SavedReport(String(x.static_json),String(x.static_sha256)),
            SavedReport(String(x.rw1_json),String(x.rw1_sha256)))
    end
    if x.schema==SAVED_SCHEMA
        return SavedReport(String(x.source_json),String(x.source_sha256))
    end
    SavedReport(text,String(expected_sha256))
end

"""
    save_report(path, saved)

Write a portable computed-report envelope and return its SHA-256 receipt.
Existing paths are refused. The original report bytes and checksum are retained
verbatim. This is not a native fit, an MCMC checkpoint or a new posterior result.
"""
function save_report(path::AbstractString, saved::SavedReport)
    body=(;schema=SAVED_SCHEMA,source_sha256=saved.source_sha256,source_json=saved.source_json)
    receipt=_save_report_envelope(path,body)
    merge(receipt,(;source_sha256=saved.source_sha256))
end

function _save_report_envelope(path,body)
    _require(!(ispath(path)||islink(path)),"preserve existing output; choose a new path")
    mkpath(dirname(abspath(path)))
    mktemp(dirname(abspath(path))) do temporary,io
        write(io,JSON3.write(body));close(io);mv(temporary,path;force=false)
    end
    (;path=abspath(path),sha256=_digest(read(path)))
end

function _warnings(x)
    o=x.original_report;warnings=String[]
    o.target.static && push!(warnings,"Static changes are fixed to zero by assumption; this is not evidence that severity did not change.")
    if hasproperty(x,:locations)
        push!(warnings,"Location levels use prior anchoring; their intervals are model-conditional and are not likelihood identification evidence.")
        for r in x.locations
            (!r.precision_passed || !r.diagnostic_passed) && push!(warnings,"$(r.parameter): location numerical criteria did not pass.")
        end
    end
    !x.numerical_qualified && push!(warnings,"Integrated numerical criteria did not pass.")
    !o.numerical_qualified && push!(warnings,"Original joint-draw numerical criteria did not pass; the original report is retained.")
    for (phase,rows) in (("retained",o.sampler),("warmup",o.warmup)), row in rows
        for key in (:n_divergences,:n_nonfinite_logdensity,:n_max_treedepth)
            row[key]>0 && push!(warnings,"$phase chain $(row.chain): $key = $(row[key]).")
        end
    end
    for row in [collect(o.raw_diagnostics);collect(o.model_diagnostics)]
        row.flag!="ok" && push!(warnings,"$(row.parameter_space) $(row.parameter): $(row.flag).")
    end
    for row in x.trajectory
        row.structurally_fixed && continue
        name="$(row.scope=="panel" ? "fixed panel" : row.rater), $(row.time)"
        row.design_status!="linked" && push!(warnings,"$name: $(row.design_status); keep prior/process dependence explicit.")
        (!row.precision_passed || !row.diagnostic_passed) && push!(warnings,"$name: contrast numerical criteria did not pass.")
        row.integration_status=="insufficient_retained_batches" && push!(warnings,"$name: conditional integration unavailable for the retained chain length; joint-draw intervals and MCSE retained.")
        if row.estimator=="conditional_gaussian_bridge"
            s=row.summary
            s.paired_mean_flag && push!(warnings,"$name: supplemental paired-mean discrepancy flag.")
            for q in s.precision.quantiles
                q.cdf_diagnostics.tail_ess===nothing && push!(warnings,"$name, quantile $(q.probability): CDF tail ESS unavailable ($(q.cdf_tail_status)).")
                (q.paired_flag || q.paired_cdf_flag) && push!(warnings,"$name, quantile $(q.probability): paired comparison flag.")
            end
        end
    end
    warnings
end

"""
    report(saved)

Return the complete source report plus its interpretation contract and warnings.
`source.original_report` preserves original numerical qualification and all
telemetry. Integration may improve empty-bin MCSE without changing a fit.
Numerical qualification is not coverage, identification or drift-detection evidence.
"""
function report(saved::SavedReport)
    source=JSON3.read(saved.source_json)
    (;api=contract(),source_sha256=saved.source_sha256,source,warnings=_warnings(source))
end

"""
    trajectory(saved; rater)

Return stored changes from the saved reference, with marginal equal-tailed
intervals, MCSE and design status. `rater` is a stored judge ID or `:panel` for
the original fixed weights. Positive values mean harsher rating. The reference
is exactly zero by definition, not an estimated zero-width severity interval.
All grid bins are retained. No new reference, mass, weights or simultaneous
band can be recovered from a computed report. Original event probabilities
remain in `report(saved).source.original_report`; integration does not replace them.
"""
function trajectory(saved::SavedReport; rater)
    x=report(saved);o=x.source.original_report
    _require(rater===:panel || (rater isa AbstractString && rater in o.target.rater_labels),"unknown judge; use :panel for fixed weights")
    label=rater===:panel ? nothing : rater
    rows=map(filter(r->r.rater==label,x.source.trajectory)) do row
        s=row.summary;fixed=row.structurally_fixed
        (;time=String(row.time),tick=row.tick,mean=fixed ? 0. : s.mean,median=fixed ? 0. : s.median,
          lower=fixed ? 0. : s.lower,upper=fixed ? 0. : s.upper,
          mean_mcse=fixed ? nothing : s.precision.mean_mcse,
          lower_mcse=fixed ? nothing : s.precision.quantiles[1].mcse,
          upper_mcse=fixed ? nothing : s.precision.quantiles[3].mcse,
          structurally_fixed=fixed,design_status=String(row.design_status),estimator=String(row.estimator),
          diagnostic_passed=row.diagnostic_passed,precision_passed=row.precision_passed)
    end
    (;rater,process=o.target.static ? :static : :rw1,reference=String(o.reference),time_unit=String(o.target.time_unit),
      interval_mass=o.interval_mass,interval_method=:pointwise_equal_tailed,link_multiplier=1.7,
      panel_weights=collect(o.panel_weights),epsilon=o.epsilon,rows,
      original_numerical_qualified=o.numerical_qualified,numerical_qualified=x.source.numerical_qualified,
      innovation_log_sd_mean=o.target.static ? nothing : o.target.mu_sigma,warnings=x.warnings,source_sha256=saved.source_sha256)
end

"""
    plot_trajectory(saved; rater, size=(1000,550), annotation_io=stdout)

Plot stored reference-relative severity medians and pointwise intervals. Load
`CairoMakie` first. Orange points mark process-only or confounded contrasts;
the reference is a diamond. All times remain on the axis. The external note
retains whole-report warnings even when one judge is selected. Save the returned
editable Figure with CairoMakie's `save`, and keep the note with the figure.
"""
function plot_trajectory(saved::SavedReport; kwargs...)
    ext=Base.get_extension(B,:BayesianMGMFRMCairoMakieExt)
    ext===nothing && throw(ArgumentError("load CairoMakie to plot an RW1 saved report"))
    ext.plot_rater_drift(saved;kwargs...)
end
include("rater_drift/records.jl")
include("rater_drift/workflow.jl")
include("rater_drift/bridge.jl")
include("rater_drift/fitting.jl")
include("rater_drift/comparison.jl")
end
