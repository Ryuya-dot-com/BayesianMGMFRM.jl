# Figures consume computed summaries only; neither loading nor drawing estimates
# a model or recomputes its Monte Carlo diagnostics.
_plot_error()=throw(ArgumentError("Expected a complete CriterionCollapse class or category report; preserve the original metadata and numerical warnings."))
_plot_finite(x)=x isa Real && !(x isa Bool) && isfinite(x)
_plot_hash(x)=x isa AbstractString && occursin(r"^[0-9a-f]{64}$",x)
function _plot_mean(row)
    _plot_finite(row.mean) && 0<=row.mean<=1 && row.interval===nothing || _plot_error()
    status=string(row.mcse_status)
    status in ("available","mcse_unavailable","degenerate_draws","insufficient_chains","insufficient_draws","nonfinite_draws") || _plot_error()
    v=row.mean_mcse
    (v===nothing || ismissing(v) || (_plot_finite(v) && v>=0)) || _plot_error()
    available=status=="available" && _plot_finite(v)
    (;probability=Float64(row.mean),mcse=available ? Float64(v) : missing,status=available ? :available : status=="available" ? :mcse_unavailable : Symbol(status))
end
_plot_number(x)=_plot_finite(x) ? string(round(x;sigdigits=4)) : "unavailable"
function _plot_labels(xs)
    labels=string.(xs)
    length(unique(labels))==length(labels) && return labels
    labels=repr.(xs)
    length(unique(labels))==length(labels) || throw(ArgumentError("Distinct levels have indistinguishable display labels."))
    labels
end
function _plot_context(report)
    all(hasproperty(report,k) for k in (:scope,:target_identity,:source_sample_content_hash,:prior,:diagnostics,:warning)) || _plot_error()
    all(hasproperty(report.scope,k) && string(getproperty(report.scope,k))==string(getproperty(SCOPE,k)) for k in keys(SCOPE)) || _plot_error()
    _plot_hash(report.target_identity) && _plot_hash(report.source_sample_content_hash) || _plot_error()
    fields=fieldnames(Prior)
    all(hasproperty(report.prior,k) for k in fields) || _plot_error()
    prior=Prior(; (k=>getproperty(report.prior,k) for k in fields)...)
    d=report.diagnostics
    d.qualified isa Bool && !isempty(d.raw) && !isempty(d.model) && !isempty(d.sampler) || _plot_error()
    rows=[d.raw;d.model]
    metric(field,op)=begin
        values=[getproperty(row,field) for row in rows]
        all(_plot_finite,values) ? _plot_number(op(values)) : "unavailable for one or more coordinates"
    end
    count_total(field,rs)=begin
        all(r->getproperty(r,field) isa Integer && !(getproperty(r,field) isa Bool) && getproperty(r,field)>=0,rs) || _plot_error()
        sum(getproperty(r,field) for r in rs)
    end
    divergences=count_total(:n_divergences,d.sampler);depth=count_total(:n_max_treedepth,d.sampler)
    warmup=count_total(:n_divergences,d.warmup)
    missing_warmup=isempty(d.warmup) || any(r->string(r.coverage)!="recorded",d.warmup)
    note="Whole-fit numerical diagnostics: $(d.qualified ? "passed" : "WARNING / not qualified"); " *
        "R-hat max $(metric(:rank_normalized_rhat,maximum)); bulk/tail ESS min $(metric(:bulk_ess,minimum)) / $(metric(:tail_ess,minimum)). " *
        "Retained divergences: $divergences; depth-limit hits: $depth; warmup divergences: $warmup" *
        (missing_warmup ? " (warmup coverage incomplete). " : ". ") *
        "These diagnostics do not qualify focal MCSE or model adequacy.\n" *
        "Prior: person precision Gamma(shape=$(prior.person_precision_shape), rate=$(prior.person_precision_rate)); " *
        "rater precision Gamma(shape=$(prior.rater_precision_shape), rate=$(prior.rater_precision_rate)); " *
        "step SD=$(prior.step_sd); class proportion Beta($(prior.class_alpha), $(prior.class_beta)); exchangeable sum-zero locations.\n" *
        string(report.warning)
    (;target_identity=String(report.target_identity),source_sample_content_hash=String(report.source_sample_content_hash),
        prior=_prior(prior),whole_fit_qualified=d.qualified,note)
end
function _class_plot_data(report)
    hasproperty(report,:classes) && hasproperty(report,:labels) && !hasproperty(report,:rows) || _plot_error()
    context=_plot_context(report);levels=collect(report.labels.rater);rows=collect(report.classes)
    length(rows)==length(levels)>=2 && length(unique(levels))==length(levels) || _plot_error()
    all(isequal(row.rater,level) for (row,level) in zip(rows,levels)) || _plot_error()
    values=_plot_mean.(rows)
    (;context...,kind=:class_probability,levels,labels=_plot_labels(levels),values,
        mcse_unavailable=count(x->ismissing(x.mcse),values))
end
function _category_plot_data(report;rater)
    hasproperty(report,:rows) && hasproperty(report,:categories) && !hasproperty(report,:classes) || _plot_error()
    context=_plot_context(report);categories=collect(report.categories);rows=collect(report.rows)
    length(categories)>=3 && all(x->x isa Integer && !(x isa Bool),categories) &&
        all(diff(categories).==1) && !isempty(rows) || _plot_error()
    # Validate all cells before selecting a rater; selection must not hide a
    # missing-MCSE warning elsewhere in the report.
    values=_plot_mean.(getproperty.(rows,:expected));raters=unique(getproperty.(rows,:rater));criteria=unique(getproperty.(rows,:criterion))
    any(isequal(rater),raters) || throw(ArgumentError("Unknown rater label: $rater"))
    K=length(categories)
    length(rows)==K*length(raters)*length(criteria) &&
        length(Set((x.rater,x.criterion,x.category) for x in rows))==length(rows) || _plot_error()
    for row in rows
        n=row.n_observations;y=row.observed_count
        n isa Integer && !(n isa Bool) && n>0 && y isa Integer && !(y isa Bool) && 0<=y<=n &&
            row.category in categories && _plot_finite(row.observed_proportion) &&
            isapprox(row.observed_proportion,y/n;atol=1e-12,rtol=1e-12) &&
            _plot_finite(row.observed_minus_expected) &&
            isapprox(row.observed_minus_expected,y/n-row.expected.mean;atol=1e-12,rtol=1e-12) || _plot_error()
    end
    for r in raters,i in criteria
        ids=findall(x->isequal(x.rater,r) && isequal(x.criterion,i),rows)
        length(ids)==K && length(unique(rows[j].n_observations for j in ids))==1 || _plot_error()
        sum(rows[j].observed_count for j in ids)==rows[first(ids)].n_observations || _plot_error()
        isapprox(sum(values[j].probability for j in ids),1.;atol=1e-8,rtol=1e-8) || _plot_error()
    end
    sum(x.n_observations for x in rows if x.category==first(categories))==report.n_observations || _plot_error()
    panels=map(criteria) do criterion
        indices=[only(findall(x->isequal(x.rater,rater) && isequal(x.criterion,criterion) && x.category==k,rows)) for k in categories]
        (;criterion,n=rows[first(indices)].n_observations,
            observed=Float64[rows[j].observed_proportion for j in indices],expected=[values[j] for j in indices])
    end
    finite_mcse=[x.mcse for x in values if !ismissing(x.mcse)]
    (;context...,kind=:category_profile,rater,criteria,labels=_plot_labels(criteria),categories,panels,
        mcse_unavailable=count(x->ismissing(x.mcse),values),
        mcse_max=isempty(finite_mcse) ? nothing : maximum(finite_mcse))
end

"""
    load_report(path; expected_sha256)

Read a computed class/category JSON report saved with `save_report`, checking its
SHA-256 against a separately retained digest and validating plotting fields and
metadata. Returns the computed data, not posterior draws. No fit, prediction RNG
or diagnostic recomputation occurs. A checksum detects byte changes; it does not
establish scientific validity or authenticate a digest from an untrusted source.
Comparison, joint-predictive and conditional held-out reports retain their
precision, fold identity and conditioning metadata.
Native result migration is not provided by this method.
"""
function load_report(path;expected_sha256)
    _plot_hash(expected_sha256) || throw(ArgumentError("expected_sha256 must be a lowercase 64-digit SHA-256 digest retained when the report was saved."))
    bytes=read(path)
    bytes2hex(B.SHA.sha256(bytes))==expected_sha256 || throw(ArgumentError("Computed-report checksum mismatch."))
    saved=JSON3.read(bytes)
    hasproperty(saved,:schema) && saved.schema=="bayesianmgmfrm.criterion_collapse_report.v1" && hasproperty(saved,:data) || _plot_error()
    report=saved.data
    if hasproperty(report,:kind)
        _operation_report_check(report)
    elseif hasproperty(report,:classes)
        _class_plot_data(report)
    elseif hasproperty(report,:rows) && !isempty(report.rows)
        _category_plot_data(report;rater=first(report.rows).rater)
    else
        _plot_error()
    end
    report
end

"""
    plot_classes(report; size=nothing, annotation_io=stdout)

Draw all rater class probabilities on a common 0–1 scale and mean MCSE on a
separate axis. No credible interval or class cutoff is invented. Unavailable
MCSE remains labelled unavailable; whole-report diagnostic/prior notes are
retained. Accepts `report(result)` or a checksum-checked `load_report` result.
Load optional CairoMakie first. Save the editable Figure and keep its external
note; `annotation_io=nothing` embeds the note instead. Never performs estimation.
"""
function plot_classes(report;kwargs...)
    ext=Base.get_extension(B,:BayesianMGMFRMCairoMakieExt)
    ext===nothing && throw(ArgumentError("Load CairoMakie to draw criterion-collapse figures."))
    ext.plot_criterion_classes(report;kwargs...)
end

"""
    plot_categories(report; rater, size=nothing, annotation_io=stdout)

Plot observed/expected category proportions for every criterion of one existing
rater, on common 0–1 axes, with expected-proportion MCSE on separate axes. MCSE
axes share a range based on the whole report. Whole-report warnings are retained
when selecting a rater. These are in-sample conditional expectations, not
replicated-count intervals, predictive tests, new-level predictions or a class
classifier. Load CairoMakie; preserve the external note with the returned Figure.
Accepts `category_report(result)` or a checksum-checked `load_report` result.
"""
function plot_categories(report;kwargs...)
    ext=Base.get_extension(B,:BayesianMGMFRMCairoMakieExt)
    ext===nothing && throw(ArgumentError("Load CairoMakie to draw criterion-collapse figures."))
    ext.plot_criterion_categories(report;kwargs...)
end
