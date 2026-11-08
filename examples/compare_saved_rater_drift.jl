# Computed reports only; no sampler, native deserialization or random generation.
using BayesianMGMFRM

function compare_saved_rater_drift(static_path,static_sha256,rw1_path,rw1_sha256,output)
    drift=BayesianMGMFRM.Experimental.RaterDrift
    static=drift.load_report(static_path;expected_sha256=static_sha256)
    rw1=drift.load_report(rw1_path;expected_sha256=rw1_sha256)
    comparison=drift.compare(static,rw1)
    answer=drift.report(comparison)
    receipt=drift.save_report(output,comparison)
    println("Descriptive model-conditional comparison; no model ranking or difference posterior.")
    println("Static changes are imposed zeros; severity levels remain uncertain.")
    println("Comparison numerical criteria passed: ",answer.comparison_numerical_qualified)
    for row in answer.locations
        println((;quantity=row.quantity,id=row.id,time=row.time,
            static=(row.static.mean,row.static.lower,row.static.upper),
            rw1=(row.rw1.mean,row.rw1.lower,row.rw1.upper)))
    end
    foreach(w->println("Warning: ",w),answer.warnings)
    println("Saved comparison: ",receipt.path,"\nSHA-256: ",receipt.sha256)
    (;comparison,answer,receipt)
end

if abspath(PROGRAM_FILE)==@__FILE__
    length(ARGS)==5 || error("Usage: compare_saved_rater_drift.jl STATIC.json STATIC_SHA256 RW1.json RW1_SHA256 NEW_OUTPUT.json")
    compare_saved_rater_drift(ARGS...)
end
