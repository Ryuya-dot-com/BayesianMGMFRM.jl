using BayesianMGMFRM

"""
    ordinal_association_saved(sample_path, output_path)

Reopen a trusted same-source/environment OrdinalAssociation sample and write
its named profile/association report. No fitting, predictive or conditional RNG.
The output must not already exist. All saved limitations remain in the report.
"""
function ordinal_association_saved(sample_path, output_path)
    A=BayesianMGMFRM.Experimental.JointRatings.OrdinalAssociation
    sample=A.load_result(sample_path)
    report=A.report(sample;interval=.95)
    A.save_report(output_path,report)
    return report
end

if abspath(PROGRAM_FILE)==@__FILE__
    length(ARGS)==2 || error("Usage: julia ordinal_association_saved.jl trusted-sample.jls new-report.json")
    report=ordinal_association_saved(ARGS...)
    println("Saved ",length(report.result.posterior)," named summaries; inspect all diagnostics, MCSE and warnings.")
end
