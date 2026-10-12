using BayesianMGMFRM

"""
    saved_integrated_report(cache_path, output_directory; reporting, kwargs...)

Read a trusted fit cache and save a public JSON/Markdown/table report bundle.
`reporting` declares optional category, agreement, named reliability-cohort and
classification and ranking requests; it never supplies assumed cohorts or response matching. All new
sections use every retained draw. This example performs no fitting. Other
`fit_report` keyword arguments pass through unchanged.
"""
function saved_integrated_report(cache_path::AbstractString, output_directory::AbstractString;
        reporting, kwargs...)
    fit=load_fit_cache(cache_path)
    report=fit_report(fit;kwargs...,reporting,view=:public)
    save_fit_report_bundle(output_directory,report;require_complete=true)
    return load_fit_report_bundle(output_directory;require_complete=true)
end
