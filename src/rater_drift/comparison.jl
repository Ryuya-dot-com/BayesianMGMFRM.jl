const COMPARISON_SCHEMA="bayesianmgmfrm.rw1_static_comparison.v1"

function _location_keys(t)
    [ [(;parameter="theta[$p]",quantity=:performance,id=t.person_labels[p],time=nothing,tick=nothing)
        for p in 1:t.P];
      [(;parameter="severity[$r,$j]",quantity=:severity,id=t.rater_labels[r],time=t.time_labels[j],tick=t.time_ticks[j])
        for j in eachindex(t.time_ticks) for r in 1:t.R] ]
end

function _location_summaries(saved)
    p=saved.plan;t=RaterDriftRecords.target(p.target)
    keys=_location_keys(t);names=getproperty.(keys,:parameter)
    raw=reduce(vcat,[c.run.draws for c in saved.chains])
    values=Matrix{Float64}(undef,size(raw,1),length(keys))
    for i in axes(raw,1)
        s=M.coordinates(t,view(raw,i,:))
        values[i,:]=[s.theta;vec(s.severity)]
    end
    precision=B.posterior_mcse(values;chains=4,parameter_names=names,
        probabilities=((1-p.interval)/2,.5,(1+p.interval)/2),parameter_space=:original_model)
    diagnostics=B._candidate_mcmc_diagnostic_rows(values,names,4;parameter_space=:original_model,
        split_chains=true,rhat_threshold=RaterDriftWorkflow.POLICY.rhat_max,
        ess_threshold=RaterDriftWorkflow.POLICY.bulk_ess_min)
    [merge(keys[k],(;estimator=:joint_draws,mean=B.Statistics.mean(view(values,:,k)),
        lower=precision[k].quantiles[1].estimate,median=precision[k].quantiles[2].estimate,
        upper=precision[k].quantiles[3].estimate,precision=precision[k],diagnostics=diagnostics[k],
        precision_passed=RaterDriftWorkflow.precision_ok((;precision=precision[k]),p.precision),
        diagnostic_passed=RaterDriftWorkflow.diagnostic_ok(diagnostics[k]))) for k in eachindex(keys)]
end

function _check_locations(x,t)
    _require(x.locations_adapter_sha256==RaterDriftRecords.digest(@__FILE__),
        "unsupported location-summary producer")
    keys=_location_keys(t);o=x.original_report;n=length(o.iterations)÷4
    _require(length(x.locations)==length(keys),"incomplete location summaries")
    for (r,k) in zip(x.locations,keys)
        _require(all(_same(r[name],B._json_export_value(getproperty(k,name))) for name in propertynames(k)),
            "location identity differs")
        _require(r.estimator=="joint_draws" && all(_finite,(r.mean,r.median,r.lower,r.upper)) &&
            r.lower<=r.median<=r.upper,"invalid location interval")
        p=r.precision
        _require(p.parameter==r.parameter==r.diagnostics.parameter && p.n_chains==4 &&
            p.draws_per_chain==n && p.total_draws==4n && length(p.quantiles)==3,
            "location chain/precision identity differs")
        _require(p.mean_mcse===nothing || (_finite(p.mean_mcse) && p.mean_mcse>=0),"invalid location mean MCSE")
        for (q,prob,value) in zip(p.quantiles,((1-o.interval_mass)/2,.5,(1+o.interval_mass)/2),
                (r.lower,r.median,r.upper))
            _require(q.probability==prob && q.estimate==value &&
                (q.mcse===nothing || (_finite(q.mcse) && q.mcse>=0)),"location quantile/MCSE differs")
        end
        _require(r.precision_passed===RaterDriftWorkflow.precision_ok(r,o.precision_policy) &&
            r.diagnostic_passed===RaterDriftWorkflow.diagnostic_ok(r.diagnostics),
            "location numerical flags differ")
    end
    if t.static
        for j in 2:length(t.time_ticks),r in 1:t.R
            a=x.locations[t.P+r];b=x.locations[t.P+(j-1)*t.R+r]
            _require(all(a[k]==b[k] for k in (:mean,:lower,:median,:upper)) &&
                a.precision.mean_mcse===b.precision.mean_mcse &&
                _same(a.precision.quantiles,b.precision.quantiles),"static severity must be identical across bins")
        end
    end
    x
end

function _check_comparison(static::SavedReport,rw1::SavedReport)
    a=JSON3.read(static.source_json);b=JSON3.read(rw1.source_json)
    _check_comparison_sources(a,b)
end

function _check_comparison_sources(a,b)
    _require(hasproperty(a,:locations) && hasproperty(b,:locations),
        "comparison requires location summaries; older computed reports cannot supply missing draws")
    x=a.original_report;y=b.original_report
    _require(x.target.static===true && y.target.static===false,"supply static then RW1 reports")
    for k in (:P,:R,:K,:person,:rater,:time,:score,:event,:person_labels,:rater_labels,
            :time_ticks,:time_labels,:time_unit)
        _require(_same(x.target[k],y.target[k]),"comparison input differs: $k")
    end
    for k in (:reference,:panel_weights,:interval_mass,:interval_method,:epsilon,:policy,:precision_policy,:conditioning)
        _require(_same(x[k],y[k]),"comparison settings differ: $k")
    end
    # Both accepted producers bind the same target code and its fixed common priors.
    _require(a.context.target_sha256==b.context.target_sha256,"comparison target definitions differ")
    nothing
end

"""Two immutable computed reports; construct with `compare` or `load_report`."""
struct SavedComparison
    static::SavedReport
    rw1::SavedReport
    function SavedComparison(static::SavedReport,rw1::SavedReport)
        _check_comparison(static,rw1)
        new(static,rw1)
    end
end

"""
    compare(static_report, rw1_report)

Create a descriptive comparison from `summarize` outputs. Require identical
ordered scoring events, outcomes, labels, full grid, categories, reference,
fixed panel, interval, tolerance and diagnostic/precision policies. The target
uses the same performance, baseline-severity and normalized-step priors in both
models. The static model has no innovation prior; RW1 retains its declared one.

Use `report(comparison)` for side-by-side performance/severity locations and
planned changes, with both original reports and all warnings. Locations use
prior anchoring. Static changes are structural zeros, while static severity
levels remain uncertain. No cross-model draw pairing, posterior difference,
model probability, predictive ranking or drift-detection accuracy is computed.
Failed numerical criteria remain visible; matching inputs do not establish
model adequacy. Older computed reports without location summaries are refused.
Save the comparison with `save_report` and restore it with `load_report`.
"""
compare(static::SavedReport,rw1::SavedReport)=SavedComparison(static,rw1)

function report(c::SavedComparison)
    a=report(c.static);b=report(c.rw1);o=a.source.original_report
    keys=(:parameter,:quantity,:id,:time,:tick)
    locations=[merge(NamedTuple{keys}(Tuple(x[k] for k in keys)),(;static=x,rw1=y))
        for (x,y) in zip(a.source.locations,b.source.locations)]
    trajectory=[(;rater=x.rater,scope=x.scope,time=x.time,tick=x.tick,static=x,rw1=y)
        for (x,y) in zip(a.source.trajectory,b.source.trajectory)]
    location_ok=all(r->r.precision_passed && r.diagnostic_passed,[collect(a.source.locations);collect(b.source.locations)])
    (;api=contract(),interpretation=:descriptive_model_conditional_comparison,
      cross_model_difference_posterior=false,model_selection=false,statistical_acceptance=false,
      common_priors=(;performance=:standard_normal,baseline_severity=:standard_normal,
          rater_steps=:normalized_sum_zero_gaussian),
      innovation_log_sd_mean=(;static=nothing,rw1=b.source.original_report.target.mu_sigma),
      interval_mass=o.interval_mass,reference=o.reference,panel_weights=collect(o.panel_weights),epsilon=o.epsilon,
      locations,trajectory,location_criteria_passed=location_ok,
      comparison_numerical_qualified=a.source.numerical_qualified && b.source.numerical_qualified && location_ok,
      sources=(;static=a,rw1=b),warnings=["Static: ".*a.warnings;"RW1: ".*b.warnings])
end

function save_report(path::AbstractString,c::SavedComparison)
    body=(;schema=COMPARISON_SCHEMA,static_json=c.static.source_json,static_sha256=c.static.source_sha256,
        rw1_json=c.rw1.source_json,rw1_sha256=c.rw1.source_sha256)
    merge(_save_report_envelope(path,body),(;static_sha256=c.static.source_sha256,rw1_sha256=c.rw1.source_sha256))
end
