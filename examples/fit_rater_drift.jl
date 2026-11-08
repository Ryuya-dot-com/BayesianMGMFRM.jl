# Including this example defines the function; only calling it runs inference.
using BayesianMGMFRM

"""Fit declared rating rows once, retaining chains and a portable computed report."""
function fit_rater_drift(rows, directory; model_options, fit_options)
    (ispath(directory) || islink(directory)) &&
        throw(ArgumentError("choose a new output directory"))
    drift=BayesianMGMFRM.Experimental.RaterDrift
    model=drift.model(rows;model_options...)
    plan=drift.prepare(model;fit_options...)
    fitted=drift.fit(plan;directory=joinpath(directory,"chains"))
    saved=drift.summarize(fitted)
    receipt=drift.save_report(joinpath(directory,"report.json"),saved)
    write(joinpath(directory,"receipt.json"),BayesianMGMFRM.JSON3.write(receipt))
    (;fitted,saved,receipt)
end
