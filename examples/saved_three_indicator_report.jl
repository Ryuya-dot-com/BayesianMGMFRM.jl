# Include this file, then supply saved report paths and separately retained checksums.
# No model fitting, posterior calculation or random generation occurs.
using BayesianMGMFRM

function saved_three_indicator_report(path; expected_sha256,
        comparison_path=nothing, comparison_sha256=nothing, output_path=nothing)
    api=BayesianMGMFRM.Experimental.ThreeIndicator
    saved=api.load_report(path;expected_sha256,comparison_path,comparison_sha256)
    result=api.report(saved)
    receipt=output_path===nothing ? nothing : api.save_report(output_path,saved)
    (;result,receipt)
end
