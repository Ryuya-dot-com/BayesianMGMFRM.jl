# API

The reference is split by workflow area for easier navigation.

Functions below are grouped by the task they support. Stable fitting uses
`fit(spec)`; the two restricted generalized families use
`BayesianMGMFRM.Experimental.fit(spec)`. Compatibility names remain callable
for older code. Research helpers are labelled separately and do not establish
that a model or diagnostic is validated for an analysis.

The optional, qualified `BayesianMGMFRM.plot_posterior`,
`BayesianMGMFRM.plot_diagnostics`, `BayesianMGMFRM.plot_predictive` and
`BayesianMGMFRM.plot_wright` functions are documented under the fitting API.
Load CairoMakie to enable their renderer; the Wright map accepts stable MFRM only.

- [Data and Design API](api-data-design.md)
- [Fitting and Artifact API](api-fitting-artifacts.md)
- [Workflow and Diagnostics API](api-workflow-diagnostics.md)
- [Validation and Evidence API](api-validation-evidence.md)
