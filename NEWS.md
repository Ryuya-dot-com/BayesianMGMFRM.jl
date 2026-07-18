# BayesianMGMFRM.jl release notes

## Unreleased

## 0.1.1

### Added

- Add `facets_report`, with `facets_compatibility_stats` as an alias, for
  explicitly approximate MFRM/RSM/PCM infit, outfit, degrees-of-freedom, and
  standardized-fit rows.
- Add clearer reporting for the guarded experimental fixed-Q confirmatory
  MGMFRM path, covering Q validation, gauge choices, initialization, prior
  policy, sampler diagnostics, predictive checks, and portable Markdown
  reports.
- Add stricter reproducibility checks for fit caches, report bundles, content
  hashes, and full-versus-cached reproduction paths.
- Add `fit_report_public` and `fit_report(...; view = :public)` for a
  reader-facing structured report that can be saved as path-free JSON, table,
  Markdown, or bundle output.
- Add automated reader-facing language checks for exported docstrings,
  representative displays and errors, and public report artifacts.
- Add a runnable guarded scalar GMFRM example alongside the minimal MFRM and
  fixed-Q confirmatory MGMFRM examples.

### Changed

- Unsupported generalized thresholds, discrimination choices, anchors, DFF
  terms, Q-matrix changes, backends, priors, and refit configurations now fail
  before numerical evaluation.
- User-facing experimental fit displays and errors now use reader-facing model
  language and actionable supported-configuration guidance.
- Refocus the published manual on installation, model scope, fitting,
  diagnostics, examples, and API reference.
- Reader-facing structured fit reports and human-readable report/dossier
  Markdown omit implementation details and machine-specific paths. Complete
  version-1 report payloads remain unchanged for compatibility. Public report
  hashes use JSON-normalized content so they remain stable after save/load,
  while user-supplied labels remain unchanged.

### Fixed

- Strengthen fixed-Q structural checks during held-out MGMFRM scoring while
  allowing a valid scoring slice to omit observations from another dimension.
- Prevent reviewed but failed evidence from being summarized as passing.
- Keep v0.1.0 report dossiers readable while converting loaded content to the
  portable reader-facing form.

## 0.1.0

- Initial registered release with long-format facet-data validation,
  MFRM/RSM/PCM design and Bayesian fitting, diagnostics, predictive checks,
  reporting artifacts, and opt-in scalar GMFRM and fixed-Q confirmatory MGMFRM
  experiments.
