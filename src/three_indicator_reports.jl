"""
    BayesianMGMFRM.Experimental.ThreeIndicator

Inspect labelled input with `inspect_input`, or read and share computed
three-outcome reports with `load_report`, `report` and `save_report`.
Prepare and fit the no-state model with explicit priors using `prepare` and `fit`, restore
its native chains with `load_fit`, and compute a report with `summarize`.
See `contract()` and the guide for its experimental interpretation limits.
"""
module ThreeIndicator
using JSON3, SHA

const SAVED_SCHEMA = "bayesianmgmfrm.three_indicator_saved_report.v1"
const SOURCES = (
    "c5dcb1e878c37e544a07665f410d96c750dc47fdd2023c3b98cde8125ce2a8d0",
    "96db7c053a72c96c86bb0a6511abb08a5b5d90c4572c8a92c8348e1d4d8a3f82",
)
const PREVIOUS_PACKAGE_PRODUCER = (:julia, "8545a288c3dfd3b365405c8282c38c0cb4f9910bba532ebad03876c2a95e0d68", "7359234bd6d723284db7f9c20664e825dd34e5783760f62a4a899ca7481aafb8")
const CONTEXT_PRODUCER = (:julia, "8545a288c3dfd3b365405c8282c38c0cb4f9910bba532ebad03876c2a95e0d68", "1d9b066ad53f5b3740c1fa0e004dcf7ae0c529bedeb3b689915799682bbdbb0d")
const HARD_DEPENDENCY_PRODUCER = (:julia, "fdd63bd611189c532c2924ffff0c24090aa51390eb2f04a134846423ac58ff3c", "a7ccaff73e531aa5362880aea3ad180ccb8b57df1a4be4712298e0e7f19defa9")
const PACKAGE_PRODUCER = (:julia, "a778f029ef43287816cf07f41d41d814e8cbde52db338e18a430d7aa8d4300d3", "a7ccaff73e531aa5362880aea3ad180ccb8b57df1a4be4712298e0e7f19defa9")
const PRODUCERS = (
    PACKAGE_PRODUCER,
    HARD_DEPENDENCY_PRODUCER,
    CONTEXT_PRODUCER,
    PREVIOUS_PACKAGE_PRODUCER,
    (:julia, SOURCES[1], "93e4051488b3b142988e6ff5f680b647eb0b5275759bc66f343cedd896795a56"),
    (:stan, SOURCES[2], "93e4051488b3b142988e6ff5f680b647eb0b5275759bc66f343cedd896795a56"),
    (:julia, SOURCES[1], "eb6d70ae8c3cfe70b3978d3e77fb46a6390a0751a315b84d67b89b667fa4d8e3"),
)
const BLOCKS = ("speaker","word","rater","token","time","l1")
_require(x, message) = x === true || throw(ArgumentError(message))
_finite(x) = x isa Real && !(x isa Bool) && isfinite(x)
_hash(x) = x isa AbstractString && occursin(r"\A[0-9a-f]{64}\z",x)
_digest(x) = bytes2hex(sha256(x))
_fields(x, names) = _require(all(n->hasproperty(x,n),names),"incomplete computed report")
_integer(x) = x isa Integer && !(x isa Bool)
_positive(x) = _finite(x) && x > 0
_mcse(x) = (_finite(x) && x>=0) || x===nothing || x in ("NaN","Inf","-Inf")
_diagnostic(d,p) = _positive(d.rank_normalized_rhat) && d.rank_normalized_rhat<=p.rhat_max &&
    _positive(d.bulk_ess) && d.bulk_ess>=p.ess_min && _positive(d.tail_ess) && d.tail_ess>=p.ess_min

"""Return the experimental no-state input, fitting and saved-report scope."""
contract() = (;status=:experimental,input_inspection=true,report_only=false,fitting=true,native_chain_import=true,historical_native_import=false,
    outcomes=(:accentedness,:comprehension_difficulty,:transcription_error),
    categories=(9,9,2),priors=(:reference,:steps,:combined),latent_state=false,scientific_acceptance=false,
    interval_method=:pointwise_equal_tailed,conditioning=:fixed_existing_event_panel,
    new_contrasts=false,new_intervals=false,stable_api=false)

function _check_prior_record(p)
    _require(hasproperty(p,:name) && p.name isa AbstractString &&
        p.name in ("reference","steps","combined"),"unsupported saved prior")
    expected=W.M.prior_record(Symbol(p.name))
    _require(Set(keys(p))==Set(keys(expected)),"incomplete or extra prior settings")
    for k in keys(expected)
        a,b=p[k],expected[k]
        valid=if b isa Tuple
            a isa AbstractVector && length(a)==length(b) && all(_finite,a) && collect(a)==collect(b)
        elseif b isa Symbol
            a isa AbstractString && a==String(b)
        elseif b isa Bool
            a===b
        else
            _finite(a) && a==b
        end
        _require(valid,"saved prior name and numerical settings disagree: $k")
    end
    p
end

function _check_source(x)
    _fields(x,(:schema,:posterior,:public_api,:statistical_acceptance,:context,:content_hash,
        :policy,:metadata,:labels,:focal_definitions,:rows,:primitive,:original,
        :sampler,:warmup,:chain_ids,:iterations,:interval_method,:conditioning,:correlations,
        :numerical_qualified,:parameter_passed,:sampler_passed,:precision_passed))
    julia=x.schema=="bayesianmgmfrm.three_indicator_workflow.v1"
    stan=x.schema=="bayesianmgmfrm.private_stan_report.v1"
    _require((julia && get(x,:kind,nothing)=="posterior") ||
        (stan && get(x,:producer,nothing)=="CmdStan"),"unsupported three-outcome report format")
    provenance=julia ? (:plan_hash,) : (:scope_sha256,:archive_hash)
    _fields(x,provenance)
    _require(x.posterior===true && x.statistical_acceptance===false,
        "only the declared experimental computed-posterior format is supported")
    _fields(x.context,(:sources,:julia,:project,:manifest,:package))
    sources=Dict(String(s.path)=>String(s.sha256) for s in x.context.sources)
    producer=(julia ? :julia : :stan, get(sources,"three_indicator_observation.jl",""),
        get(sources,"three_indicator_workflow.jl",""))
    _require(length(sources)==length(x.context.sources)==3 &&
        producer in PRODUCERS &&
        get(sources,"mgmfrm_lkj_cholesky_candidate.jl","")=="bec6d709ab6e1b7daa69614cec78628fda68ae26802e5ea78426c43bd7cd691a",
        "unsupported report target or producer")
    _require(x.public_api===(producer in (PACKAGE_PRODUCER,HARD_DEPENDENCY_PRODUCER,CONTEXT_PRODUCER,PREVIOUS_PACKAGE_PRODUCER)),"report API provenance differs")
    _require(hasproperty(x,:listener_support)===(producer in (PACKAGE_PRODUCER,HARD_DEPENDENCY_PRODUCER,CONTEXT_PRODUCER)),
        "listener support provenance differs")
    _require(hasproperty(x,:prior)===(producer in (PACKAGE_PRODUCER,HARD_DEPENDENCY_PRODUCER)),"prior provenance differs")
    hasproperty(x,:prior) && _check_prior_record(x.prior)
    _require(all(_hash,(x.content_hash,x.context.project,x.context.manifest,x.context.package)) &&
        all(name->_hash(x[name]),provenance),
        "invalid saved identity")
    _require(x.interval_method=="pointwise_equal_tailed" &&
        x.conditioning=="fixed_existing_event_panel" && x.correlations=="marginal_pre_projection",
        "unsupported interpretation")
    m=x.metadata
    _fields(m,(:outcomes,:direction,:binary_coding,:predictor_units,:scoring_version,:source))
    _require(collect(m.outcomes)==["accentedness","comprehension_difficulty","transcription_error"] &&
        m.direction=="higher_is_adverse" && m.binary_coding=="1=correct;2=incorrect",
        "outcome order or direction differs")
    _require(all(v->v isa AbstractString && !isempty(strip(v)),
        (m.predictor_units,m.scoring_version,m.source)),"missing scoring or input provenance")
    for name in (:event,:speaker,:rater,:word,:token,:cohort)
        _fields(x.labels,(name,));v=x.labels[name]
        _require(!isempty(v) && all(a->a isa AbstractString && !isempty(a),v) &&
            length(unique(v))==length(v),"invalid saved labels")
    end
    p=x.policy;_fields(p,(:interval,:rhat_max,:ess_min,:bfmi_min,:probability_mcse_max,:other_mcse_max))
    _require(p.interval==.95 && p.rhat_max==1.01 && p.ess_min==400 &&
        p.bfmi_min==.3 && p.probability_mcse_max==.005 && p.other_mcse_max==.02,
        "unsupported saved numerical policy")
    f=x.focal_definitions
    _fields(f,(:panel_label,:events,:weights,:speaker_pairs,:listener_pairs))
    _require(f.panel_label isa AbstractString && !isempty(f.panel_label) &&
        !isempty(f.events) && length(f.events)==length(f.weights) &&
        length(unique(f.events))==length(f.events) &&
        all(e->_integer(e)&&1<=e<=length(x.labels.event),f.events) &&
        all(w->_finite(w)&&w>=0,f.weights) && isapprox(sum(f.weights),1.;atol=1e-12,rtol=0),
        "invalid fixed panel")
    expected=Pair{String,String}[]
    for d in 1:3
        append!(expected,["panel_probability[$d,$k]"=>"probability" for k in 1:(d==3 ? 2 : 9)])
        d<=2 && push!(expected,"panel_expected_rating[$d]"=>"rating")
    end
    push!(expected,"panel_correct_probability"=>"probability")
    for (family,pairs,labels) in (("speaker",f.speaker_pairs,x.labels.speaker),("listener",f.listener_pairs,x.labels.rater))
        _require(!isempty(pairs),"named contrasts are required")
        for pair in pairs
            _fields(pair,(:label,:left,:right))
            _require(pair.label isa AbstractString && !isempty(pair.label) &&
                all(i->_integer(i)&&1<=i<=length(labels),(pair.left,pair.right)) &&
                pair.left!=pair.right,"invalid named contrast")
            if family=="listener"
                _fields(pair,(:l1,:time))
                _require(_integer(pair.l1)&&1<=pair.l1<=3&&_finite(pair.time),"invalid listener context")
            end
            append!(expected,["$family/$(pair.label)/$d"=>"location" for d in 1:3])
        end
    end
    append!(expected,["correlation/$b/$i,$j"=>"correlation" for b in BLOCKS for j in 1:2 for i in j+1:3])
    _require(length(unique(first.(expected)))==length(expected)==length(x.rows),"incomplete or duplicate focal rows")
    for (r,(name,scale)) in zip(x.rows,expected)
        _fields(r,(:name,:scale,:mean,:median,:lower,:upper,:precision,:diagnostics,
            :precision_passed,:diagnostic_passed,:mcse_limit))
        _require(r.name==name && r.scale==scale && all(_finite,(r.mean,r.median,r.lower,r.upper)) &&
            r.lower<=r.median<=r.upper,"invalid focal summary or units")
        bounds=scale=="probability" ? (0.,1.) : scale=="rating" ? (1.,9.) : scale=="correlation" ? (-1.,1.) : (-Inf,Inf)
        _require(bounds[1]<=r.lower<=r.upper<=bounds[2] && bounds[1]<=r.mean<=bounds[2],"summary outside its scale")
        limit=scale=="probability" ? p.probability_mcse_max : p.other_mcse_max
        _fields(r.precision,(:mean_mcse,:quantiles))
        _require(r.mcse_limit==limit && length(r.precision.quantiles)==3,"inconsistent precision policy")
        for (q,prob,value) in zip(r.precision.quantiles,((1-p.interval)/2,.5,(1+p.interval)/2),(r.lower,r.median,r.upper))
            _fields(q,(:probability,:estimate,:mcse))
            _require(q.probability==prob && q.estimate==value,"interval and precision rows disagree")
            _require(_mcse(q.mcse),"invalid or negative MCSE")
        end
        _require(_mcse(r.precision.mean_mcse),"invalid or negative mean MCSE")
        ok=_finite(r.precision.mean_mcse) && 0<=r.precision.mean_mcse<=limit &&
            all(q->_finite(q.mcse)&&0<=q.mcse<=limit,r.precision.quantiles[[1,3]])
        _fields(r.diagnostics,(:rank_normalized_rhat,:bulk_ess,:tail_ess))
        _require(r.precision_passed===ok && r.diagnostic_passed===_diagnostic(r.diagnostics,p),
            "inconsistent focal numerical flags")
    end
    _require(!isempty(x.primitive) && !isempty(x.original),"whole-fit diagnostics are required")
    for r in [collect(x.primitive);collect(x.original)]
        _fields(r,(:parameter,:parameter_space,:flag,:quality_gate_applicable,:rank_normalized_rhat,:bulk_ess,:tail_ess))
        _require(r.quality_gate_applicable isa Bool,"invalid diagnostic applicability")
    end
    _require(length(x.sampler)==length(x.warmup)==4,"four chains of telemetry are required")
    for group in (x.sampler,x.warmup), (i,r) in enumerate(group)
        _fields(r,(:chain,:n_divergences,:n_nonfinite_logdensity,:n_max_treedepth))
        _require(r.chain==i && all(v->_integer(v)&&v>=0,
            (r.n_divergences,r.n_nonfinite_logdensity,r.n_max_treedepth)),"invalid chain telemetry")
    end
    for r in x.sampler
        _fields(r,(:e_bfmi,:n_invalid_sampler_values))
        _require(_integer(r.n_invalid_sampler_values)&&r.n_invalid_sampler_values>=0,"invalid sampler count")
    end
    n=length(x.iterations)÷4
    _require(n>=10 && collect(x.chain_ids)==repeat(1:4;inner=n) &&
        collect(x.iterations)==repeat(1:n;outer=4),"incomplete chain/iteration axes")
    parameters=all(r->!r.quality_gate_applicable || _diagnostic(r,p),[collect(x.primitive);collect(x.original)]) &&
        all(r->r.diagnostic_passed,x.rows)
    telemetry=all(r->r.n_divergences==r.n_nonfinite_logdensity==r.n_invalid_sampler_values==0 &&
        _positive(r.e_bfmi)&&r.e_bfmi>=p.bfmi_min,x.sampler)
    precision=all(r->r.precision_passed,x.rows)
    _require(x.parameter_passed===parameters && x.sampler_passed===telemetry &&
        x.precision_passed===precision && x.numerical_qualified===(parameters&&telemetry&&precision),
        "inconsistent whole-report numerical flags")
    hasproperty(x,:listener_support) && _check_listener_support(x)
    x
end

function _check_comparison(c,x)
    _fields(c,(:julia_report_hash,:stan_report_hash,:julia_qualified,:stan_qualified,:qualified_agreement,:rows,:interpretation))
    side=x.schema=="bayesianmgmfrm.three_indicator_workflow.v1" ? :julia : :stan
    _require(c[Symbol(side,:_report_hash)]==x.content_hash &&
        c[Symbol(side,:_qualified)]===x.numerical_qualified && length(c.rows)==length(x.rows),
        "comparison does not belong to this report")
    flags=NamedTuple[]
    for (r,s) in zip(c.rows,x.rows)
        _require(r.name==s.name && length(r.quantities)==3,"comparison rows differ")
        for (q,kind) in zip(r.quantities,("mean","lower","upper"))
            _require(q.kind==kind && q[side]==s[Symbol(kind)] && q.review_flag isa Bool &&
                all(_finite,(q.julia,q.stan,q.difference,q.combined_mcse,q.standardized)) &&
                q.combined_mcse>0 && q.difference==q.stan-q.julia &&
                q.standardized==q.difference/q.combined_mcse &&
                q.review_flag===(abs(q.standardized)>3),"inconsistent saved comparison")
            q.review_flag && push!(flags,(;name=String(r.name),quantity=Symbol(kind),
                difference=q.difference,combined_mcse=q.combined_mcse,standardized=q.standardized))
        end
    end
    _require(c.qualified_agreement===(c.julia_qualified && c.stan_qualified && isempty(flags)),
        "inconsistent saved agreement flag")
    flags
end

struct SavedReport
    source_json::String
    source_sha256::String
    comparison_json::Union{Nothing,String}
    comparison_sha256::Union{Nothing,String}
    function SavedReport(text::String,digest::String,comparison,comparison_digest)
        _require(_hash(digest)&&_digest(text)==digest,"report checksum differs")
        x=_check_source(JSON3.read(text))
        _require((comparison===nothing)===(comparison_digest===nothing),"comparison and its checksum must be supplied together")
        if comparison!==nothing
            _require(comparison isa String && _hash(comparison_digest)&&_digest(comparison)==comparison_digest,"comparison checksum differs")
            _check_comparison(JSON3.read(comparison),x)
        end
        new(text,digest,comparison,comparison_digest)
    end
end

function _read(path,expected)
    _require(_hash(expected),"supply a separately retained SHA-256 receipt")
    text=read(path,String);_require(_digest(text)==expected,"file checksum differs")
    text
end

"""
    load_report(path; expected_sha256, comparison_path=nothing, comparison_sha256=nothing)

Read a supported Julia/Stan computed report, or a portable `save_report` copy.
Supply SHA-256 receipts retained when the files were produced. Checksums detect
changed bytes; they do not authenticate a producer or establish model validity.
An optional saved engine comparison retains its review flags and is checked
against this report. No comparison is recomputed from posterior draws.
An envelope already includes its comparison; do not supply another one.
Model and producer versions must form a supported combination. Unknown exports
are refused; preserve the original file and receipt instead of editing provenance.
"""
function load_report(path::AbstractString;expected_sha256,comparison_path=nothing,comparison_sha256=nothing)
    text=_read(path,expected_sha256);x=JSON3.read(text)
    _fields(x,(:schema,))
    if x.schema==SAVED_SCHEMA
        _require(comparison_path===nothing && comparison_sha256===nothing,"the saved copy already contains its comparison")
        _fields(x,(:source_json,:source_sha256,:comparison_json,:comparison_sha256))
        return SavedReport(String(x.source_json),String(x.source_sha256),
            x.comparison_json===nothing ? nothing : String(x.comparison_json),
            x.comparison_sha256===nothing ? nothing : String(x.comparison_sha256))
    end
    _require((comparison_path===nothing)===(comparison_sha256===nothing),"comparison and checksum are required together")
    comparison=comparison_path===nothing ? nothing : _read(comparison_path,comparison_sha256)
    SavedReport(text,String(expected_sha256),comparison,comparison_sha256===nothing ? nothing : String(comparison_sha256))
end

"""
    report(saved)

Return a flat `rows` table with saved means, pointwise intervals, endpoint MCSE
and numerical flags, together with the full `source`, original panel/contrasts,
outcome directions and warnings. Location contrasts are adverse-location
differences, not score differences or common log odds ratios. Correlations are
marginal before centering. Missing comparisons are explicitly marked; passing
numerical criteria does not establish scientific acceptance or equivalence.
`listener_support` reports each named listener/L1's observed position range,
count and extrapolation status when recorded by the producer. Older reports
return `status=:not_recorded`; the original summaries do not contain enough
input information to reconstruct those ranges. Keep that uncertainty visible.
These marginal checks do not establish joint covariate overlap or identification.
`prior` contains the numerical specification and `prior_provenance` is
`:recorded` for new reports. For older recognized reference-only producers,
it is `:producer_reference`: the source code fixes that prior, but the original
report did not record it explicitly. Original source bytes remain unchanged.
"""
function report(saved::SavedReport)
    x=JSON3.read(saved.source_json)
    comparison=saved.comparison_json===nothing ? nothing : JSON3.read(saved.comparison_json)
    flags=comparison===nothing ? NamedTuple[] : _check_comparison(comparison,x)
    warnings=String["These are model/prior-conditional computed summaries, not scientific acceptance or identification evidence."]
    prior_provenance=hasproperty(x,:prior) ? :recorded : :producer_reference
    prior=W.M.prior_record(hasproperty(x,:prior) ? Symbol(x.prior.name) : :reference)
    prior_provenance===:producer_reference && push!(warnings,
        "The reference prior is identified from the recognized producer; it was not explicitly recorded in this older report.")
    support=if hasproperty(x,:listener_support)
        append!(warnings,_support_warnings(x.listener_support))
        _support_view(x.listener_support)
    else
        push!(warnings,"Listener position support was not recorded; extrapolation cannot be assessed from this computed report.")
        (;status=:not_recorded,scope=:listener_l1_position_range,rows=NamedTuple[])
    end
    !x.numerical_qualified && push!(warnings,"Whole-report numerical criteria did not pass.")
    comparison===nothing && push!(warnings,"No engine comparison was supplied; cross-engine agreement is not assessed.")
    for f in flags;push!(warnings,"Engine comparison: $(f.name) $(f.quantity) retains a review flag.");end
    for (phase,group) in (("retained",x.sampler),("warmup",x.warmup)), r in group
        for key in (:n_divergences,:n_nonfinite_logdensity,:n_max_treedepth)
            r[key]>0 && push!(warnings,"$phase chain $(r.chain): $key = $(r[key]).")
        end
    end
    for r in [collect(x.primitive);collect(x.original)]
        !(r.flag in ("ok","structurally_fixed")) && push!(warnings,"$(r.parameter_space) $(r.parameter): $(r.flag).")
    end
    rows=map(x.rows) do r
        (!r.precision_passed || !r.diagnostic_passed) && push!(warnings,"$(r.name): focal numerical criteria did not pass.")
        (;name=String(r.name),scale=Symbol(r.scale),mean=r.mean,median=r.median,lower=r.lower,upper=r.upper,
          mean_mcse=r.precision.mean_mcse,lower_mcse=r.precision.quantiles[1].mcse,
          upper_mcse=r.precision.quantiles[3].mcse,precision_passed=r.precision_passed,diagnostic_passed=r.diagnostic_passed)
    end
    (;api=contract(),source_sha256=saved.source_sha256,source=x,rows,
      focal_definitions=x.focal_definitions,metadata=x.metadata,prior,prior_provenance,interval_mass=x.policy.interval,
      numerical_qualified=x.numerical_qualified,listener_support=support,warnings,
      comparison=(;status=comparison===nothing ? :not_supplied : :saved_descriptive_comparison,
          source_sha256=saved.comparison_sha256,source=comparison,flags))
end

"""
    save_report(path, saved)

Write a portable JSON envelope preserving the exact source and optional
comparison bytes. Return its SHA-256 receipt and keep it separately. Existing
paths, including symbolic links, are refused. This saves computed results,
not native draws, a changed interval, or an MCMC checkpoint.
"""
function save_report(path::AbstractString,saved::SavedReport)
    _require(!(ispath(path)||islink(path)),"preserve existing output; choose a new path")
    body=(;schema=SAVED_SCHEMA,source_json=saved.source_json,source_sha256=saved.source_sha256,
        comparison_json=saved.comparison_json,comparison_sha256=saved.comparison_sha256)
    mkpath(dirname(abspath(path)))
    mktemp(dirname(abspath(path))) do temporary,io
        write(io,JSON3.write(body));close(io);hardlink(temporary,path)
    end
    (;path=abspath(path),sha256=_digest(read(path)),source_sha256=saved.source_sha256,
      comparison_sha256=saved.comparison_sha256)
end
include("three_indicator_input.jl")
include("three_indicator_context.jl")
include("three_indicator_fitting.jl")
include("three_indicator/concurrent.jl")
include("three_indicator/concurrent_reports.jl")
include("three_indicator/concurrent_coordinates.jl")
include("three_indicator/concurrent_workflow.jl")
include("three_indicator/concurrent_predictive.jl")
include("three_indicator/concurrent_prior_predictive.jl")
const ConcurrentPrior=Concurrent.Prior
const ConcurrentInput=Concurrent.Input
const ConcurrentTarget=Concurrent.Target
end
