# Package-root and submodule API classifications for the 0.2.x release line.
#
# Layer 1 (`BayesianMGMFRM` root exports) contains only core practitioner types
# and unified lifecycle verbs. Layer-2 mathematical and interoperability tools
# live in `BayesianMGMFRM.GlassBox`, research/simulation/benchmark protocols
# live in `BayesianMGMFRM.ValidationSuite`, and earlier `0.1.x` compatibility
# aliases live in `BayesianMGMFRM.Legacy`.

const _ROOT_API_LAYER1_BINDINGS = Tuple(sort!(Symbol[
    # Core Types (6)
    :FacetData,
    :AbstractMFRMSpec,
    :AbstractMFRMFit,
    :SamplingProgress,
    :ValidationIssue,
    :ValidationReport,
    # Design, Priors & Simulation (7)
    :design_summary,
    :mfrm_spec,
    :prior_draw,
    :prior_predictive_check,
    :simulate,
    :validate_design,
    :with_options,
    # Fitting & Worker Checkpointing (6)
    :collect_fit,
    :fit,
    :prepare_fit,
    :progress_snapshot,
    :run_chain_worker,
    :worker_status,
    # Qualification, Summaries, Contrasts, Equating & Decisions (12)
    :anchor_linking_summary,
    :category_summary,
    :classification,
    :contrast,
    :diagnostics,
    :facet_summary,
    :plausible_values,
    :posterior_mcse,
    :posterior_summary,
    :qualify,
    :ranking,
    :reliability,
    # Prediction, Model Comparison, Sensitivity & Persistence (10)
    :compare_models,
    :criteria,
    :event_probabilities,
    :load_fit,
    :load_report,
    :predict,
    :predictive_check,
    :prior_sensitivity,
    :save_fit,
    :save_report,
]; by = String))

const _GLASS_BOX_EXPORTED_BINDINGS = Tuple(sort!(Symbol[GlassBox._GLASS_BOX_NAMES...]; by = String))

const _ROOT_API_RESEARCH_BINDINGS = Tuple(sort!(Symbol[ValidationSuite._RESEARCH_ROOT_NAMES...]; by = String))

const _VALIDATION_SUITE_EXPORTED_BINDINGS = Tuple(sort!(Symbol[
    ValidationSuite._RESEARCH_ROOT_NAMES...,
    ValidationSuite._CORRELATION_2D_STUDY_NAMES...,
    ValidationSuite._EXCHANGE_SCHEMA_NAMES...,
    :RecoveryPlanning,
    :contract,
]; by = String))

const _LEGACY_EXPORTED_BINDINGS = Tuple(sort!(Symbol[Legacy._LEGACY_NAMES...]; by = String))

function _root_api_contract()
    return (;
        schema = "bayesianmgmfrm.root_api_contract.v2",
        release_line = "0.2.x",
        growth_policy = :curated_layer1,
        owner = :package_maintainers,
        manual_policy = (;
            layer1_practitioner = :required,
            glass_box = :documented_layer2,
            validation_suite = :optional_explicitly_nonstable,
            legacy = :compatibility_migration,
        ),
        layer1_practitioner = _ROOT_API_LAYER1_BINDINGS,
        glass_box = _GLASS_BOX_EXPORTED_BINDINGS,
        validation_suite = _VALIDATION_SUITE_EXPORTED_BINDINGS,
        legacy = _LEGACY_EXPORTED_BINDINGS,
    )
end
