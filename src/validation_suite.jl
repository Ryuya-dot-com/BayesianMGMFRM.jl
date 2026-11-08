"""
    BayesianMGMFRM.ValidationSuite

Dedicated namespace for simulation-protocol, recovery-study, calibration-pilot,
cross-engine benchmark, and evidence-manifest utilities.

Separating these validation harnesses from the primary practitioner workflow
keeps everyday measurement analysis concise while preserving transparent,
programmatic access to every methodological verification protocol in the
package. Compatibility bindings from the 0.1.x release line remain available at
the package root.
"""
module ValidationSuite

const _ROOT = parentmodule(@__MODULE__)
const _EXP = getfield(_ROOT, :Experimental)

const RecoveryPlanning = getfield(_EXP, :RecoveryPlanning)

const _RESEARCH_ROOT_NAMES = (
    :benchmark_result_row,
    :benchmark_summary,
    :case_study_provenance_manifest,
    :comparison_evidence_row,
    :comparison_evidence_summary,
    :evidence_artifact_schema_policy,
    :falsification_rule_summary,
    :falsification_rules,
    :local_dependence_calibration_contract,
    :local_dependence_calibration_pilot_check,
    :local_dependence_calibration_pilot_contract,
    :local_dependence_calibration_pilot_preflight,
    :local_dependence_calibration_row,
    :local_dependence_calibration_summary,
    :local_dependence_simulation_grid,
    :mgmfrm_decision_stability_score,
    :mgmfrm_predictive_recovery_score,
    :mgmfrm_response_stress_fit_attempts,
    :mgmfrm_response_stress_plan,
    :mgmfrm_response_stress_preflight,
    :mgmfrm_validation_analysis_contract,
    :mgmfrm_validation_execution_design_contract,
    :mgmfrm_validation_isolated_resource_probe,
    :mgmfrm_validation_isolated_resource_review,
    :mgmfrm_validation_primary_grid_candidates,
    :mgmfrm_validation_primary_grid_preflight,
    :mgmfrm_validation_primary_resource_plan,
    :mgmfrm_validation_protocol,
    :mgmfrm_validation_replication_precision,
    :mgmfrm_validation_resource_probe,
    :mgmfrm_validation_scaled_resource_plan,
    :mgmfrm_validation_short_nuts_resource_probe,
    :parameter_recovery,
    :parameter_recovery_plot_data,
    :parameter_recovery_summary,
    :release_gate_check,
    :release_scope_summary,
    :simulate_local_dependence,
    :simulate_mgmfrm_response_stress,
    :simulate_mgmfrm_validation_primary_candidate,
    :simulation_grid,
    :simulation_grid_summary,
    :stan_validation_row,
    :stan_validation_summary,
)

const _CORRELATION_2D_STUDY_NAMES = (
    :free_latent_correlation_2d_candidate,
    :free_latent_correlation_2d_contract,
    :free_latent_correlation_2d_diagnostics,
    :free_latent_correlation_2d_known_truth_fixture,
    :free_latent_correlation_2d_oracle_profile,
    :free_latent_correlation_2d_recovery_pilot,
    :free_latent_correlation_2d_sampler_smoke,
    :free_latent_correlation_2d_state,
    :free_latent_correlation_2d_study_apply_result,
    :free_latent_correlation_2d_study_dry_run,
    :free_latent_correlation_2d_study_feasibility_decision,
    :free_latent_correlation_2d_study_ledger,
    :free_latent_correlation_2d_study_plan,
    :free_latent_correlation_2d_study_resource_probe,
    :free_latent_correlation_2d_study_run_unit,
    :free_latent_correlation_2d_study_score,
    :free_latent_correlation_2d_study_unit_preflight,
)

for _sym in _RESEARCH_ROOT_NAMES
    @eval const $(_sym) = getfield(_ROOT, $(QuoteNode(_sym)))
    @eval export $(_sym)
end

for _sym in _CORRELATION_2D_STUDY_NAMES
    @eval const $(_sym) = getfield(_EXP, $(QuoteNode(_sym)))
    @eval export $(_sym)
end

export RecoveryPlanning, contract

"""
    contract()

Return the structured inventory of validation-suite and study-protocol
bindings grouped by methodological domain.
"""
function contract()
    return (;
        schema = "bayesianmgmfrm.validation_suite.v1",
        status = :research_and_validation_protocol,
        root_compatibility_preserved = true,
        groups = (;
            recovery_and_simulation = (
                :RecoveryPlanning,
                :parameter_recovery,
                :parameter_recovery_plot_data,
                :parameter_recovery_summary,
                :simulation_grid,
                :simulation_grid_summary,
            ),
            local_dependence_calibration = (
                :local_dependence_calibration_contract,
                :local_dependence_calibration_pilot_check,
                :local_dependence_calibration_pilot_contract,
                :local_dependence_calibration_pilot_preflight,
                :local_dependence_calibration_row,
                :local_dependence_calibration_summary,
                :local_dependence_simulation_grid,
                :simulate_local_dependence,
            ),
            mgmfrm_validation_protocol = (
                :mgmfrm_decision_stability_score,
                :mgmfrm_predictive_recovery_score,
                :mgmfrm_response_stress_fit_attempts,
                :mgmfrm_response_stress_plan,
                :mgmfrm_response_stress_preflight,
                :mgmfrm_validation_analysis_contract,
                :mgmfrm_validation_execution_design_contract,
                :mgmfrm_validation_isolated_resource_probe,
                :mgmfrm_validation_isolated_resource_review,
                :mgmfrm_validation_primary_grid_candidates,
                :mgmfrm_validation_primary_grid_preflight,
                :mgmfrm_validation_primary_resource_plan,
                :mgmfrm_validation_protocol,
                :mgmfrm_validation_replication_precision,
                :mgmfrm_validation_resource_probe,
                :mgmfrm_validation_scaled_resource_plan,
                :mgmfrm_validation_short_nuts_resource_probe,
                :simulate_mgmfrm_response_stress,
                :simulate_mgmfrm_validation_primary_candidate,
            ),
            free_latent_correlation_2d_study = _CORRELATION_2D_STUDY_NAMES,
            benchmark_and_cross_engine = (
                :benchmark_result_row,
                :benchmark_summary,
                :comparison_evidence_row,
                :comparison_evidence_summary,
                :falsification_rule_summary,
                :falsification_rules,
                :stan_validation_row,
                :stan_validation_summary,
            ),
            evidence_and_scope_manifests = (
                :case_study_provenance_manifest,
                :evidence_artifact_schema_policy,
                :release_gate_check,
                :release_scope_summary,
            ),
        ),
    )
end

end
