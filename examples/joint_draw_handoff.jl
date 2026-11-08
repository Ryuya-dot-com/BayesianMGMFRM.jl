module JointDrawHandoff

using BayesianMGMFRM, SHA
using BayesianMGMFRM: JSON3

"""
    JointDrawHandoff.write_json(path, fitted::MFRMFit)

Write an example row-oriented JSON handoff from an existing scalar fit, without
sampling. Every parameter in a row belongs to the same retained posterior draw.
The returned SHA-256 checks the written file; the source artifact hash identifies
its Julia artifact and is not a checksum of this different JSON representation.
"""
function write_json(path::AbstractString, fitted::MFRMFit)
    ispath(path) && throw(ArgumentError("Handoff destination already exists: $path"))
    all(isfinite, fitted.draws) || throw(ArgumentError("JSON handoff requires finite draws."))
    artifact = fit_artifact(fitted; view=:public, include_draws=true,
        include_log_posterior=false, include_environment=false)
    report = fit_report(fitted; view=:public, require_complete=true,
        include_prior_predictive=false, include_posterior_predictive=false,
        include_grouped_predictive=false, include_category_functioning=false,
        include_rater_homogeneity=false, include_calibration=false,
        include_waic=false, include_loo=false, include_artifact=false)
    payload = (; schema="bayesianmgmfrm.example_joint_draw_handoff.v1",
        parameter_names=artifact.parameter_names,
        chain_ids=artifact.draw_index.chain_ids,
        iterations=artifact.draw_index.iterations,
        draws=[collect(row) for row in eachrow(artifact.draws)],
        metadata=artifact.fit_metadata, model=artifact.model_manifest,
        diagnostics=report.diagnostics, warmup=report.warmup,
        prior_policy=report.prior_policy, fixed_coordinates=report.fixed_coordinates,
        posterior=report.posterior, mcse=posterior_mcse(fitted),
        source=(; design_identity=design_identity(fitted.design),
            artifact_content_hash=artifact.content_hash.value),
        interpretation="Rows preserve joint uncertainty conditional on the fitted model and prior. Reusing them does not fit a joint outcome model or establish decision calibration.")
    mkpath(dirname(path))
    open(path, "w") do io
        JSON3.write(io, payload)
        write(io, '\n')
    end
    return (; path=abspath(path), sha256=bytes2hex(open(sha256, path)),
        n_draws=size(fitted.draws,1), n_parameters=size(fitted.draws,2))
end

end
