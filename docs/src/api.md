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

The optional, qualified `BayesianMGMFRM.plot_posterior`,
`BayesianMGMFRM.plot_diagnostics`, `BayesianMGMFRM.plot_predictive` and
`BayesianMGMFRM.plot_wright` and `BayesianMGMFRM.plot_pathway` functions are documented under the fitting API.
Load CairoMakie to enable their renderer; the Wright map accepts stable MFRM only.

- [Data and Design API](api-data-design.md)
- [Fitting and Artifact API](api-fitting-artifacts.md)
- [Workflow and Diagnostics API](api-workflow-diagnostics.md)
- [Saved-fit Reporting Candidate API](api-saved-reporting.md) (qualified development API)
- [Prediction and Recovery Candidate API](api-prediction-recovery.md) (qualified development API)
- [Experimental Model API](api-experimental.md)
- [Validation and Evidence API](api-validation-evidence.md)
