# Saved summaries only: this adapter never calls a fit, predictive generator or RNG.
const _CONCURRENT_PLOT_SCHEMA = "bayesianmgmfrm.concurrent_plot.v1"
const _CONCURRENT_PLOT_METRICS = ("accentedness/expected_score",
    "comprehension_difficulty/expected_score", "correct_probability")
_is_concurrent_plot_input(r) = hasproperty(r,:schema) &&
    (r.schema == _CONCURRENT_PLOT_SCHEMA || r.schema in _TI_MOD.ConcurrentPredictive.SCHEMAS ||
        r.schema in _TI_MOD.ConcurrentWorkflow.REPORT_SCHEMAS)

function _concurrent_plot_names(metadata)
    d=metadata.definitions
    R=_TI_MOD.ConcurrentReports; require=R.require
    require(d.direction=="higher_is_adverse" && d.binary_coding=="1=correct;2=incorrect", "unsupported outcome direction/coding")
    if d.operation=="preliminary_contrasts"
        defs=d.comparisons; prefix="contrast"; middle="/difference/"
        require(length(defs)==length(R.DEFINITIONS) && d.selection.additional_row_weight==0 &&
            collect(d.selection.cohorts)==collect(_TI_MOD.Concurrent.SOURCES[1:2]),"contrast panel differs")
        for (x,definition) in zip(defs,R.DEFINITIONS)
            require((x.name,x.level,x.left_group,x.right_group)==definition,"contrast identity differs")
            n=d.design.preliminary_listeners*(x.level=="condition" ? 20 : x.level=="block" ? 25 : 50)
            require(x.n_left==x.n_right==n && x.raters_left==x.raters_right==d.design.preliminary_listeners &&
                x.left_weight==1/n && x.right_weight==-1/n,"contrast reference weights differ")
        end
        labels=String[x.name for x in defs]
    elseif d.operation=="eng_reference"
        defs=d.speakers; prefix="speaker_style"; middle="/"
        f=d.reference
        require(length(f.listeners)==d.design.preliminary_listeners && allunique(f.listeners) &&
            length(f.words)==d.design.words && allunique(f.words) &&
            f.listener_weight==1/length(f.listeners) && f.word_weight==1/length(f.words),"profile reference weights differ")
        require((f.block,f.within_block_position,f.within_time,f.previous_condition,f.word_lag_log,f.speaker_lag_log)==
            (1,13,0.,"ENG_natural",0.,0.),"profile context differs")
        require(!isempty(defs) && allunique(x.speaker_style for x in defs) &&
            length(d.recordings)==length(defs)*d.design.words && allunique(x.token for x in d.recordings),"profile support differs")
        for x in defs
            records=filter(y->y.speaker_style==x.speaker_style,d.recordings)
            require(x.n_words==length(records)==d.design.words && Set(y.word for y in records)==Set(f.words) &&
                x.cross_study_recordings==count(y->y.cross_study_extrapolation,records),"profile/extrapolation identity differs")
            require(all(y->y.observed_preliminary_listeners isa Integer &&
                0<=y.observed_preliminary_listeners<=length(f.listeners) &&
                y.cross_study_extrapolation===(y.observed_preliminary_listeners==0),records),"extrapolation flag differs")
        end
        labels=["$(x.speaker_style) (extrapolated $(x.cross_study_recordings)/$(x.n_words))" for x in defs]
    else
        throw(ArgumentError("saved posterior plots require contrasts or eng_reference reports"))
    end
    (; names=["$prefix[$i]$middle$metric" for metric in _CONCURRENT_PLOT_METRICS for i in eachindex(defs)],
        labels, operation=d.operation=="preliminary_contrasts" ? "contrasts" : "eng_reference")
end

function _concurrent_plot_data(r)
    r.schema==_CONCURRENT_PLOT_SCHEMA && return _check_concurrent_plot_data(r)
    predictive=r.schema in _TI_MOD.ConcurrentPredictive.SCHEMAS
    predictive ? _TI_MOD.ConcurrentPredictive.check_report(r) : _TI_MOD.ConcurrentWorkflow.check_report(r)
    # Large repeated parameter diagnostics and adaptation matrices stay in the original report.
    metadata=Dict{String,Any}(String(k)=>v for (k,v) in pairs(r)
        if !(String(k) in ("rows","content_hash","qualification","adaptation","adaptation_plan")))
    metadata["qualification"]=Dict(String(k)=>v for (k,v) in pairs(r.qualification) if String(k)!="diagnostics")
    if predictive
        rows=r.rows; failed=String[]; diagnostic_failed=String[]
    else
        selection=_concurrent_plot_names(r)
        by_name=Dict(x.name=>x for x in r.rows)
        all(n->haskey(by_name,n),selection.names) || throw(ArgumentError("missing focal plot quantities"))
        rows=[by_name[n] for n in selection.names]
        failed=String[x.name for x in r.rows if !x.precision_passed]
        diagnostic_failed=String[x.name for x in r.rows if !x.diagnostic_passed]
    end
    body=(;schema=_CONCURRENT_PLOT_SCHEMA,source_schema=String(r.schema),
        source_report_hash=String(r.content_hash),source_fit_hash=String(r.source_fit_hash),
        metadata,rows,source_rows_count=length(r.rows),precision_failure_names=failed,
        diagnostic_failure_names=diagnostic_failed,new_fits=0,new_predictive_replications=0)
    d=_TI_MOD.ConcurrentReports.normalized(body);d["content_hash"]=_cache_hash(d)
    _check_concurrent_plot_data(JSON3.read(JSON3.write(d)))
end

function _check_concurrent_plot_data(r)
    R=_TI_MOD.ConcurrentReports;F=_TI_MOD.ConcurrentWorkflow;P=_TI_MOD.ConcurrentPredictive
    require=R.require
    d=R.normalized(r);h=pop!(d,"content_hash",nothing)
    require(r.schema==_CONCURRENT_PLOT_SCHEMA && R.hashstring(h) && _cache_hash(d)==h,"saved plot content changed")
    require(R.hashstring(r.source_report_hash) && R.hashstring(r.source_fit_hash) &&
        r.source_fit_hash==r.metadata.source_fit_hash && r.source_schema==r.metadata.schema,
        "saved plot source binding differs")
    require(r.new_fits==0 && r.new_predictive_replications==0 &&
        r.metadata.scientific_acceptance===false,"saved plot provenance differs")
    m=r.metadata
    _TI_MOD.Concurrent.check_observation_contract(m.model)
    require(!isempty(r.rows) && allunique(x.name for x in r.rows),"unique plot row IDs required")
    if r.source_schema in P.SCHEMAS
        require(r.source_rows_count==202 && isempty(r.precision_failure_names) &&
            isempty(r.diagnostic_failure_names),"predictive plot scope differs")
        # Reuse the complete count, panel, endpoint, law and identity validator.
        source=R.normalized(m);source["rows"]=r.rows
        source=R.normalized(source)
        source["content_hash"]=_cache_hash(source)
        P.check_report(JSON3.read(JSON3.write(source)))
    else
        require(r.source_schema in F.REPORT_SCHEMAS && m.posterior===true && m.kind=="posterior" &&
            m.conditioning=="joint_draws_existing_effects" && m.interval_method=="pointwise_equal_tailed",
            "unsupported posterior plot provenance")
        F.bounds(m.interval)
        require(R.normalized(m.policy)==R.normalized(merge(F.POLICY,(;interval=Float64(m.interval)))),"precision policy differs")
        selection=_concurrent_plot_names(m)
        require(Set(x.name for x in r.rows)==Set(selection.names),"focal plot selection differs")
        expected_count=selection.operation=="contrasts" ? 23*3*length(m.definitions.comparisons) :
            23*(length(m.definitions.recordings)+length(m.definitions.speakers))
        require(r.source_rows_count==expected_count,"original focal denominator differs")
        require(m.draws_per_chain==m.controls.ndraws && collect(m.chain_ids)==collect(1:m.controls.chains),"posterior chain IDs differ")
        require(m.numerical_qualified===(m.qualification.qualified && m.precision_passed && m.focal_diagnostic_passed),"source qualification differs")
        for (names,passed) in ((r.precision_failure_names,m.precision_passed),(r.diagnostic_failure_names,m.focal_diagnostic_passed))
            require(allunique(names) && length(names)<=r.source_rows_count && passed===isempty(names),"source failure accounting differs")
        end
        require(r.source_rows_count>=length(r.rows) && !isempty(m.warnings),"full report scope/warnings required")
        lo,hi=F.bounds(m.interval)
        for x in r.rows
            unit=endswith(x.name,"correct_probability") ? "probability" : "rating"
            limit=unit=="probability" ? F.POLICY.probability_mcse_max : F.POLICY.other_mcse_max
            require(x.unit==unit && x.mcse_limit==limit && all(R.finite,(x.mean,x.sd,x.median,x.lower,x.upper)) &&
                x.sd>=0 && x.lower<=x.median<=x.upper,"posterior units or interval differ")
            p=x.mcse;dg=x.diagnostics
            require(length(p.quantiles)==3 && all(isapprox(y.probability,z;atol=1e-14,rtol=0) for
                (y,z) in zip(p.quantiles,(lo,.5,hi))),"quantile identities differ")
            available(v)=R.finite(v) && v>=0
            precise=p.mcse_status=="available" && available(p.mean_mcse) && p.mean_mcse<=limit &&
                all(y->available(y.mcse) && y.mcse<=limit,p.quantiles)
            diagnostic=available(dg.rank_normalized_rhat) && dg.rank_normalized_rhat<=F.POLICY.rhat_max &&
                available(dg.bulk_ess) && dg.bulk_ess>=F.POLICY.ess_min && available(dg.tail_ess) && dg.tail_ess>=F.POLICY.ess_min
            require(x.precision_passed===precise && x.diagnostic_passed===diagnostic &&
                (!precise)==(x.name in r.precision_failure_names) &&
                (!diagnostic)==(x.name in r.diagnostic_failure_names),"selected precision/diagnostics differ")
            require(p.n_chains==m.controls.chains && p.draws_per_chain==m.draws_per_chain,"MCSE chain layout differs")
        end
    end
    r
end

function _concurrent_plot_note(data,view)
    m=data.metadata;level=round(100m.interval;digits=2)
    if data.source_schema in _TI_MOD.ConcurrentPredictive.SCHEMAS
        note="Posterior predictive check, existing levels. Observed counts versus replicated counts; $level% pointwise predictive intervals, not simultaneous bands. " *
            (view===:joint ? "Color is 100 × (observed − replicated mean) / panel denominator, in percentage points; the symmetric scale is shared across panels. Outlined squares mark cells outside the interval with stable endpoint screens; outlined circles mark outside cells with unresolved screens. " :
            "Diamonds are observed counts; blue points and bars are replicated medians and intervals. Binary categories are 1 = correct, 2 = error. ") *
            "Whole-fit qualified: $(m.posterior_fit_qualified). Discrete endpoint screens unresolved: $(m.discrete_endpoints_unresolved)/404. Quantile MCSE is unavailable, not zero. "
    else
        note="Posterior mean and $level% pointwise equal-tailed credible intervals, not future-response intervals. " *
            "Higher ordinal ratings mean more accented speech or greater comprehension difficulty; higher correctness probability means more correct responses. " *
            "Hollow markers flag selected quantities with failed/unavailable precision or diagnostics. Whole-fit qualified: $(m.qualification.qualified); full focal report qualified: $(m.numerical_qualified). " *
            "Full report: $(length(data.precision_failure_names))/$(data.source_rows_count) precision failures and $(length(data.diagnostic_failure_names)) diagnostic failures; only $(length(data.rows)) selected quantities are displayed. " *
            (view===:contrasts ? "Differences follow the saved left-minus-right definitions and reference weights. " :
            "Profiles average over the saved preliminary-listener reference and word weights. Labels show recordings with no preliminary listeners; those are cross-study extrapolations, not new-listener validation. ")
    end
    warnings=String.(m.warnings)
    hasproperty(m,:source_report_warnings) && append!(warnings,String.(m.source_report_warnings))
    note * "Source report $(data.source_report_hash); fit $(data.source_fit_hash). No new fitting or predictive replication. " * join(unique(warnings)," ")
end

function _plot_concurrent_report(r;kind=:posterior,view=nothing,return_data::Bool=false,size=nothing,annotation_io=stdout)
    data=_concurrent_plot_data(r)
    predictive=data.source_schema in _TI_MOD.ConcurrentPredictive.SCHEMAS
    expected=predictive ? :predictive : :posterior
    kind===expected || throw(ArgumentError("this saved report requires kind=:$expected"))
    operation=predictive ? :predictive : Symbol(_concurrent_plot_names(data.metadata).operation)
    selected=view===nothing ? (predictive ? :marginal : operation) : view
    allowed=predictive ? (:marginal,:joint) : (operation,)
    selected in allowed || throw(ArgumentError("unsupported saved-report view; choose $allowed"))
    extension=Base.get_extension(@__MODULE__,:BayesianMGMFRMCairoMakieExt)
    extension===nothing && throw(ArgumentError("saved-report plots require `using CairoMakie`"))
    figure=extension.plot_concurrent_report(data;view=selected,size,annotation_io)
    return_data ? (;figure,data) : figure
end
