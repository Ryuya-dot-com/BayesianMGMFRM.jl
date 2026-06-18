# BayesianMGMFRM.jl release notes

## Unreleased

- Clarify that the current public package is a data validation, design, and
  minimal MFRM fitting scaffold, not a full GMFRM/MGMFRM fitting API.
- Introduce `validate_design` / `ValidationReport` as the public terminology for
  pre-fit design checks.
- Preserve requested DFF/bias validation evidence in `mfrm_spec`.
- Reject boolean score columns instead of silently treating them as `0/1`.
- Report empty data with a dedicated `:empty_data` validation error.
- Use numeric ordering for numeric facet labels.
- Warn when item/category cells are unobserved or an item uses only one category,
  because partial-credit thresholds may be weakly informed.
- Add reference constraints for the minimal additive design: first rater and
  item levels are fixed, and threshold steps use a sum-to-zero reconstruction.
- Add an initial Bayesian `fit` API for the minimal MFRM/RSM/PCM scaffold,
  returning `MFRMFit` posterior draws from a `backend = :julia` random-walk
  Metropolis sampler.
- Add `posterior_predict` and `posterior_predictive_check` for posterior
  replicated scores and compact observed-vs-replicated summaries.
- Add `prior_predict` and `prior_predictive_check` for prior replicated scores
  and compact observed-vs-replicated summaries before fitting.
- Stabilize scalar faithful log-probability paths with log-sum-exp.
- Add a non-optional scalar known-answer fixture for the analytic log-density
  and gradient, removing the default skipped Stan-fixture test path.
- Check that raw and contrast scalar parameterizations agree at the same
  constrained parameter values.
- Add the scalar Stan reference model, a BridgeStan-generated scalar
  log-density fixture, and a regeneration script under `scripts/`.
- Connect the scalar faithful validation target to real `FacetData` input for
  one-item designs, replacing the previous phantom-data-only construction path.
- Add a minimal Documenter site for the data-validation workflow and public API,
  with a CI documentation build job.
- Extend the GitHub Actions test matrix to Windows in addition to Ubuntu and
  macOS.
- Add `scripts/pre_registration_gate.jl` and a CI pre-registration gate job for
  clean import, metadata, Aqua, example, docs/test, diff, and wording checks.
