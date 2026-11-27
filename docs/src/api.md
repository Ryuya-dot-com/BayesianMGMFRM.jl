# API

!!! note "Development manual"
    Use the [matching source and installation instructions](installation.md).
    This manual describes a development snapshot, not an accepted stable release.
    Model support and scientific acceptance remain as stated on each page.

The reference is split by workflow area for easier navigation.

If you do not know a function name, use [Find an answer by task](index.md#find-by-task).
For the calculation behind a result, start with the [worked model explanation](rating-model-theory.md),
[exact equations](model-equations.md), or [posterior computation](fitting.md#calculation-route).
The API pages below specify arguments, defaults, returned values and restrictions;
they complement those explanations.

In Julia, load the package and type `?BayesianMGMFRM` for the entry workflow,
`?FacetData` for data input or `?fit` for fitting. Specialized fitting
has separate help: `?BayesianMGMFRM.Experimental.fit`. In a script or notebook,
use `@doc BayesianMGMFRM.Experimental.fit` instead of REPL `?` syntax.
See [Julia help and executable examples](learning-guide.md#Use-Julia-help-and-examples)
for the distinction between reading documentation and running a script.

Functions below are grouped by the task they support. Standard 1D MFRM,
GMFRM and scale-identified MGMFRM specifications use `mfrm_spec` and `fit(spec)`.
Other model-specific entry points are described in their guides. Compatibility
names remain callable for older code.

## Specification and fit types

Use `AbstractMFRMSpec` and `AbstractMFRMFit` for functions that accept standard
workflow objects across model families and estimation methods:

```julia
my_design(spec::AbstractMFRMSpec) = design_summary(spec)
my_summary(fitted::AbstractMFRMFit) = design_summary(fitted)
```

Concrete types retain their model-specific fields and operations. For example,
JMLE/MMLE fits do not provide MCMC draws or the full joint Bayesian posterior.
Portable handoff bundles and computed reports are separate objects.

The compatibility types `FacetDesign`, `MFRMPrior`, `FacetSpec`, and `MFRMFit`
are exported by `BayesianMGMFRM.Legacy`. Existing qualified names such as
`BayesianMGMFRM.FacetSpec` still refer to the same concrete types. In old
scripts that used them unqualified, import the names they need, for example
`using BayesianMGMFRM.Legacy: FacetSpec, MFRMFit`. For functions intended to
accept the standard v0.2 route, change their annotations to the abstract types.
`FacetData` remains a root export and can build the standard specification with
`mfrm_spec(data; prior = :default)`.

## Unified Practitioner Lifecycle

Model families share the following workflow vocabulary. **Methods and return
values depend on the input model**: not every family implements every verb or
option. Start with a model's guide and inspect its contract before combining
operations. Multi-worker checkpointing is a model-specific option, not a
required step in an ordinary analysis:

1. **Specify & Inspect Design:** `FacetData`, `validate_design`,
   `design_summary`, `mfrm_spec`, `Experimental.joint_rating_spec`, `with_options`
2. **Check Priors & Simulate:** `prior_draw`, `simulate`, `prior_predictive_check`
3. **Fit & Checkpoint:** `fit` (plus multi-worker `prepare_fit`,
   `run_chain_worker`, `worker_status`, `collect_fit`, `progress_snapshot`)
4. **Qualify, Summarize & Decide:** `qualify`, `diagnostics`,
   `posterior_summary`, `posterior_mcse`, `facet_summary`, `category_summary`,
   `contrast`, `plausible_values`, `anchor_linking_summary`, `predict`,
   `event_probabilities`, `reliability`, `ranking`, `classification`,
   `predictive_check`, `criteria`, `compare_models`, `prior_sensitivity`
5. **Visualize & Persist:** `BayesianMGMFRM.plot(fit; kind = :posterior)`
   (load CairoMakie first), `save_fit` / `load_fit`, `save_report` / `load_report`

## Glass-Box Researcher & Submodule Surfaces

Methodological researchers inspecting exact coordinate parameterizations,
Rao–Searle Schur-complement contrast bases, triangular Jacobians, analytical
gradients, CmdStan data dictionaries, or sparse category design matrices can load
`using BayesianMGMFRM.GlassBox` to bring `contract`, `parameter_names`,
`facet_basis`, `coordinates`, `to_ncp_reference`, `from_ncp_reference`,
`reparameterize_point`, `reparameterize_draws`, `log_jacobian_to_ncp`,
`logprior`, `loglikelihood`, `pointwise_loglikelihood`, `logposterior`,
`logdensity_and_gradient`, `stan_data`, `sampler_controls`, `MRCML`,
`StanAdapter`, `PortableHandoff`, and `ModelOperationMatrix` into scope
(see [Data and Design API](api-data-design.md)).

Simulation-study, calibration-pilot, and benchmark harnesses live in
`BayesianMGMFRM.ValidationSuite` (see [Validation and Evidence API](api-validation-evidence.md)),
and earlier `0.1.x` compatibility aliases live in `BayesianMGMFRM.Legacy`.

- [Data and Design API](api-data-design.md)
- [Fitting and Artifact API](api-fitting-artifacts.md)
- [Workflow and Diagnostics API](api-workflow-diagnostics.md)
- [Saving and Reopening Results API](api-saved-reporting.md)
- [Prediction and Recovery API](api-prediction-recovery.md)
- [Model Extensions API](api-experimental.md)
- [Validation and Evidence API](api-validation-evidence.md)
