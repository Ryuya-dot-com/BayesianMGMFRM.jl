using BayesianMGMFRM

"""
    saved_prediction_workflow(caches::Pair...; directory, dataset_id,
        observation_ids, comparison_axis, criterion=:waic, baseline=nothing,
        reporting_by_model=nothing)

Compare all eight common saved-fit types, inspect diagnostics and parameter
MCSE, and save/reopen public reports. Fixed-coefficient MFRM requires canonical
records. The original five-type calls retain their report options and results.
Supply one vector of persistent rating IDs in the common original row order.
Use a new output directory. No fitting or figure rendering is performed.
Warnings and unresolved scientific acceptance remain visible in the result.
Optional `reporting_by_model` is a dictionary containing every model label,
mapped to `nothing` or a named tuple of `category`, `agreement`, and/or
`reliability`/`classification`/`ranking`/`alpha`/`icc` options from `fit_report`. Cohorts, targets and response matching
remain explicit. Dataset/rating IDs come from the common comparison arguments;
do not repeat them in the per-model options. The original three fit types omit
their extra legacy category/homogeneity/calibration sections in this focused
example. Their criterion tables retain native row-index semantics; persistent
rating IDs remain in the common comparison and requested integrated sections.
"""
function saved_prediction_workflow(caches::Pair...; directory, dataset_id,
        observation_ids::AbstractVector, comparison_axis, criterion=:waic,
        baseline=nothing, reporting_by_model=nothing)
    fits=[string(name)=>load_fit_cache(path) for (name,path) in caches]
    original=Union{MFRMFit,GMFRMFit,MGMFRMFit}
    supported=Union{original,BayesianMGMFRM.Experimental.NormalizedMGMFRMFit,
        BayesianMGMFRM.Experimental.CorrelatedMGMFRMFit,
        BayesianMGMFRM.MultidimensionalMFRMFit,
        BayesianMGMFRM.Experimental.CorrelatedMFRMFit,
        BayesianMGMFRM.Experimental.ExchangeableMFRMFit}
    all(pair->last(pair) isa supported,fits) || throw(ArgumentError(
        "this example requires one of the eight common saved-fit types"))
    criterion in (:waic,:raw_loo) || throw(ArgumentError("criterion must be :waic or :raw_loo"))
    ispath(directory) && throw(ArgumentError("use a new report directory"))
    comparison=BayesianMGMFRM.compare_predictions(fits...; dataset_id,observation_ids,
        comparison_axis,criterion,baseline,se_unit=:none)
    reporting = if reporting_by_model === nothing
        Dict(name=>nothing for (name,_) in fits)
    else
        reporting_by_model isa AbstractDict || throw(ArgumentError("reporting_by_model must be a dictionary"))
        options=Dict(string(name)=>value for (name,value) in reporting_by_model)
        length(options)==length(reporting_by_model) && Set(keys(options))==Set(first.(fits)) ||
            throw(ArgumentError("reporting_by_model must contain every model label exactly once"))
        for value in values(options)
            value === nothing && continue
            value isa NamedTuple && Set(keys(value)) ⊆ Set((:category,:agreement,:reliability,:classification,:ranking,:alpha,:icc)) ||
                throw(ArgumentError("model reporting options are category, agreement, reliability, classification, ranking, alpha and icc; use the common dataset/rating IDs"))
        end
        options
    end
    # Prepare every report before writing so an unsupported input leaves no partial bundle.
    prepared=map(fits) do (name,fit)
        request=reporting[name]
        if request !== nothing && (get(request,:category,nothing)!==nothing || get(request,:agreement,nothing)!==nothing || get(request,:alpha,nothing)!==nothing || get(request,:icc,nothing)!==nothing)
            request=merge(request,(;dataset_id,observation_ids))
        end
        options=fit isa original ? (;include_category_functioning=false,
            include_rater_homogeneity=false,include_calibration=false) : (;dataset_id,observation_ids)
        (; model=name, diagnostics=diagnostics(fit), parameter_mcse=posterior_mcse(fit),
        report=fit_report(fit;options...,view=:public,reporting=request,
            include_waic=true,include_loo=true,include_posterior_predictive=false,
            require_complete=true))
    end
    models=map(enumerate(prepared)) do (i,result)
        path=joinpath(directory,"model-$i")
        save_fit_report_bundle(path,result.report;require_complete=true)
        merge(result,(;report=load_fit_report_bundle(path;require_complete=true)))
    end
    return (; comparison,models)
end
