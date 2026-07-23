# Bayesian Fitting

`BayesianMGMFRM.jl` fits identified MFRM/RSM/PCM designs and exposes two narrow
generalized configurations behind explicit experimental opt-in. Model
validation and design inspection should happen before sampling.

## Supported MFRM/RSM/PCM Fit

```julia
using BayesianMGMFRM

ratings = (
    examinee = ["E1", "E1", "E1", "E1", "E2", "E2", "E2", "E2"],
    rater = ["R1", "R2", "R1", "R2", "R1", "R2", "R1", "R2"],
    item = ["I1", "I1", "I2", "I2", "I1", "I1", "I2", "I2"],
    score = [0, 1, 2, 0, 1, 2, 0, 2],
)

data = FacetData(ratings;
    person = :examinee,
    rater = :rater,
    item = :item,
    score = :score,
)
validation = validate_design(data)
validation.passed || error(validation)

spec = mfrm_spec(data;
    thresholds = :partial_credit,
    validation_report = validation,
)
design = getdesign(spec)

fit_result = fit(design;
    backend = :advancedhmc,
    ndraws = 500,
    warmup = 500,
    chains = 4,
    seed = 20260718,
)
```

The rating-scale and partial-credit threshold regimes share the same workflow.
Inspect [`constraint_table`](@ref), [`identification_declarations`](@ref), and
[`model_manifest`](@ref) when reviewing the parameterization.

## Backends and Sampler Controls

[`fit`](@ref) supports:

- `backend = :julia` for a simple random-walk Metropolis implementation;
- `backend = :advancedhmc` for direct AdvancedHMC/NUTS sampling;
- `backend = :turing` for the package target wrapped in Turing/NUTS.

Use short runs only to verify wiring. For substantive work, choose the number
of chains, warmup, retained draws, target acceptance, tree depth, metric, and
initialization strategy before examining the results. Record a seed when exact
replay is part of the analysis plan.

Sampler success is necessary but not sufficient. Review:

- [`sampler_diagnostics`](@ref) for acceptance and HMC warnings;
- [`mcmc_diagnostics`](@ref) for parameter-level R-hat and ESS;
- [`parameter_block_diagnostics`](@ref) for block-level summaries;
- [`diagnostics`](@ref) for the compact overall status;
- prior and posterior predictive checks, calibration, and sensitivity results.

Very short chains commonly produce unreliable R-hat and ESS values even when
the example completes without an exception.

## Experimental Generalized Fitting

Generalized fitting is deliberately outside this stable fitting surface. Use
the [Experimental Generalized Models](experimental.md) page for the scalar
rater-consistency GMFRM and fixed-Q confirmatory MGMFRM contracts, examples,
and migration guidance.

Both configurations require `thresholds = :partial_credit`.
Both configurations require no anchors and no fitted DFF terms. Scalar GMFRM
uses `discrimination = :rater`; fixed-Q MGMFRM uses the compatibility selector
`discrimination = :none`. Custom generalized prior objects are not supported.
The legacy
`fit(spec; experimental = true)` form remains source-compatible, but
`BayesianMGMFRM.Experimental.fit` is the canonical entry point for new work.

## Predictive Checks and Model Comparison

Use [`prior_predictive_check`](@ref) before interpreting a fit and
[`posterior_predictive_check`](@ref) afterward. [`calibration_table`](@ref)
provides expected-score and category-probability calibration rows.

WAIC, LOO, PSIS-LOO, and K-fold summaries require a clearly stated prediction
target and compatible observations across compared models. Treat Pareto-k and
held-out diagnostics as part of the result. A numerical ranking alone is not a
scientific superiority claim.

## Reports and Reproducibility

[`fit_report`](@ref) collects metadata, diagnostics, design checks, posterior
summaries, predictive results, calibration, and optional comparison rows.
The complete version-1 payload retains its fields for machine compatibility.
Use `fit_report(fit; view = :public)` or [`fit_report_public`](@ref) for a
portable report shared with readers. [`fit_report_markdown`](@ref) applies the
same projection. It preserves user-supplied person, rater, item, parameter,
category, and dimension labels, and its JSON-normalized content hash remains
stable after a save/load round trip.
Report dossiers saved by v0.1.0 remain readable; loading converts them to the
same portable form before rendering or resaving.

Use [`fit_artifact`](@ref) for a hash-checked fit artifact and [`cached_fit`](@ref)
when cache identity is explicitly part of the workflow. A cache hit should be
accepted only when model, data, prior, initialization, backend, and sampler
controls match the requested fit.

## FACETS-Compatible Descriptive Rows

[`facets_report`](@ref) and [`facets_compatibility_stats`](@ref) return a
separately labelled posterior-mean plugin summary for supported MFRM/RSM/PCM
fits. The rows use unit weights, Wright--Masters fourth-moment degrees of
freedom, and a capped Wilson--Hilferty transformation. They are approximate,
do not propagate full posterior uncertainty, and do not claim numerical
equivalence with FACETS. Generalized fits are rejected.

## Interpretation Boundary

- Diagnose rating-design support before interpreting facet differences.
- Separate statistical uncertainty from practical magnitude.
- Treat DFF output as screening unless a fitted, identified effect model is
  explicitly supported.
- Do not generalize fixed-Q results to exploratory multidimensional models.
- Report sampler warnings, prediction targets, prior choices, and unsupported
  model features alongside substantive results.
