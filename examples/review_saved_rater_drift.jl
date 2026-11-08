# Review an existing computed report; no sampling or random generation.
using BayesianMGMFRM

function review_saved_rater_drift(input, sha256, output; rater=:panel)
    drift=BayesianMGMFRM.Experimental.RaterDrift
    saved=drift.load_report(input;expected_sha256=sha256)
    result=drift.report(saved)
    data=drift.trajectory(saved;rater)
    receipt=drift.save_report(output,saved)
    println("Change from ",data.reference,"; positive values mean harsher rating.")
    println("Pointwise interval mass: ",data.interval_mass,"; model link multiplier: 1.7")
    for row in data.rows
        println(row)
    end
    println("Original numerical qualification: ",data.original_numerical_qualified)
    println("Integrated numerical qualification: ",data.numerical_qualified)
    foreach(w->println("Warning: ",w),result.warnings)
    println("Saved computed report: ",receipt.path,"\nSHA-256: ",receipt.sha256)
    (;saved,result,data,receipt)
end

if abspath(PROGRAM_FILE)==@__FILE__
    length(ARGS) in (3,4) || error("Usage: review_saved_rater_drift.jl INPUT.json SHA256 NEW_OUTPUT.json [JUDGE_ID]")
    review_saved_rater_drift(ARGS[1],ARGS[2],ARGS[3];rater=length(ARGS)==4 ? ARGS[4] : :panel)
end
