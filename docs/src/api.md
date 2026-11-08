# API

!!! note "Unreleased documentation preview — 13 October 2026"
    This manual includes unreleased interfaces and examples. It is not the
    documentation of an installed release. Model support and scientific
    acceptance remain as stated on each page.

The reference is split by workflow area for easier navigation.

If you do not know a function name, use [Find an answer by task](index.md#find-by-task).
For the calculation behind a result, start with the [worked model explanation](rating-model-theory.md),
[exact equations](model-equations.md), or [posterior computation](fitting.md#calculation-route).
The API pages below specify arguments, defaults, returned values and restrictions;
they complement those explanations.

In Julia, load the package and type `?BayesianMGMFRM` for the entry workflow,
`?FacetData` for data input or `?fit` for the stable fitter. Experimental fitting
has separate help: `?BayesianMGMFRM.Experimental.fit`. In a script or notebook,
use `@doc BayesianMGMFRM.Experimental.fit` instead of REPL `?` syntax.
See [Julia help and executable examples](learning-guide.md#Use-Julia-help-and-examples)
for the distinction between reading documentation and running a script.

Functions below are grouped by the task they support. Stable fitting uses
`fit(spec)`; the documented multidimensional and generalized routes use
`BayesianMGMFRM.Experimental.fit(spec)`. Compatibility names remain callable
for older code. Research helpers are labelled separately and do not establish
that a model or diagnostic is validated for an analysis.

## Unified Practitioner Lifecycle

Every model family in `BayesianMGMFRM` connects through one concise sequence of
verbs:

1. **Specify & Inspect Design:** `FacetData`, `design_summary`, `mfrm_spec`,
   `Experimental.joint_rating_spec`, `with_options`
2. **Check Priors & Simulate:** `prior_draw`, `simulate`, `prior_predictive_check`
3. **Fit & Checkpoint:** `fit` (plus multi-worker `prepare_fit`,
   `run_chain_worker`, `worker_status`, `collect_fit`)
4. **Qualify, Summarize & Decide:** `qualify`, `diagnostics`,
   `posterior_summary`, `facet_summary`, `category_summary`, `contrast`,
   `event_probabilities`, `reliability`, `ranking`, `classification`,
   `predictive_check`, `criteria` (`waic`, `psis_loo`), `compare_models`,
   `prior_sensitivity`
5. **Visualize & Persist:** `BayesianMGMFRM.plot(fit; kind = :posterior)`
   (load CairoMakie first), `save_fit` / `load_fit`, `save_report` / `load_report`

## Glass-Box Researcher Transparency Surface

Methodological researchers inspecting exact coordinate parameterizations,
Rao–Searle Schur-complement contrast bases, triangular Jacobians, analytical
gradients, or CmdStan data dictionaries can call `contract`, `parameter_names`,
`facet_basis`, `coordinates`, `to_ncp_reference`, `from_ncp_reference`,
`reparameterize_point`, `reparameterize_draws`, `log_jacobian_to_ncp`,
`logprior`, `loglikelihood`, `pointwise_loglikelihood`, `logposterior`,
`logdensity_and_gradient`, `stan_data`, and `sampler_controls` directly
(see [Data and Design API](api-data-design.md)).

Simulation-study, calibration-pilot, and benchmark harnesses are organized in
`BayesianMGMFRM.ValidationSuite` (see [Validation and Evidence API](api-validation-evidence.md)).

- [Data and Design API](api-data-design.md)
- [Fitting and Artifact API](api-fitting-artifacts.md)
- [Workflow and Diagnostics API](api-workflow-diagnostics.md)
- [Saving and Reopening Results API](api-saved-reporting.md)
- [Prediction and Recovery API](api-prediction-recovery.md)
- [Experimental Model API](api-experimental.md)
- [Validation and Evidence API](api-validation-evidence.md)
