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
- `backend = :turing` for the package target wrapped in Turing/NUTS;
- `backend = :cmdstan` for stable MFRM/RSM/PCM and both guarded generalized
  configurations through an external CmdStan installation. Use
  `BayesianMGMFRM.Experimental.fit` for GMFRM/MGMFRM.

Run `cmdstan_backend_check()` to inspect CmdStan, `stanc`, `make`, and C++
compiler availability without compiling a model. The first fit for a supported
family compiles its package-owned Stan model into a temporary machine-local
cache. It uses the same Julia raw/identified parameter order and prior scales, imports the
standard CmdStan sampler columns, and checks generated pointwise log likelihoods
against Julia at every retained draw. `target_accept` maps to CmdStan's
`adapt delta`; thinning remains one. CmdStan failures raise `CmdStanError`
instead of being converted to a missing result.

For both guarded generalized families, every retained raw draw is transformed
through the Julia identification map before the common fit, diagnostics, and
prediction interfaces are built. MGMFRM remains fixed-Q and
identity-correlation only. `cached_fit` and parallel chain execution are not
yet connected to CmdStan. CmdStan remains optional for package
installation, and no backend is declared faster or more accurate without a
same-target analysis.

Use short runs only to verify wiring. For substantive work, choose the number
of chains, warmup, retained draws, target acceptance, tree depth, metric, and
initialization strategy before examining the results. Record a seed when exact
replay is part of the analysis plan.

For one consolidated wiring check across stable MFRM, guarded scalar GMFRM,
and guarded fixed-Q MGMFRM, run:

```sh
julia --project=. scripts/run_cmdstan_backend_validation.jl smoke
```

This fits the same simulated response data with AdvancedHMC and CmdStan under
both a fully crossed layout and a connected sparse layout. The smoke profile
uses one very short chain and therefore checks execution, finite outputs,
identification constraints, pointwise likelihood construction, and predictive
probabilities only. It prints sampler warnings and descriptive backend
differences, but does not label them as convergence, backend-equivalence, or
parameter-recovery evidence. The larger `pilot` profile uses two chains with
100 warmup and 100 retained draws per chain and computes the existing R-hat/ESS
diagnostics; it is still a local diagnostic pilot rather than a repeated
simulation study. Printed elapsed times include Julia compilation and the
current CmdStan executable-cache state, so they are resource observations, not
backend benchmarks. Errors are not swallowed: the runner stops with the
original typed failure. Set
`BAYESIANMGMFRM_CMDSTAN_PAIRED_TESTS=true` to opt this 12-fit smoke matrix into
the test suite; it is excluded from routine tests to control compute cost.

After the wiring smoke succeeds, a small known-truth recovery pilot can be run
separately:

```sh
julia --project=. scripts/run_cmdstan_recovery_pilot.jl 2
```

The optional integer is the number of paired replications. The runner uses a
nonzero deterministic truth, simulates one sparse dataset per model and
replication, fits that same dataset with both backends, and evaluates MAE,
RMSE, interval coverage, and block error on the common identified direct
scale. It also reports divergence, maximum tree-depth, R-hat, bulk ESS, and
tail ESS separately. No pilot threshold or backend ranking is applied.
`BAYESIANMGMFRM_CMDSTAN_RECOVERY_PILOT_TESTS=true` opts a one-replication run
into the test suite; routine tests only check its simulation and aggregation
contract without running MCMC.

The current two-chain, 100-warmup/100-retained budget is deliberately a
resource and operability probe rather than analysis guidance. R-hat, ESS,
sampler warnings, and recovery errors are printed so a later validation
protocol can choose a feasible budget; they do not change the pilot's status
and are not pass/fail criteria. Any later recovery evaluation must freeze its
budget and decision rules first and use fresh simulation seeds rather than
reusing this pilot as evidence.

Sampler success is necessary but not sufficient. Review:

- [`sampler_diagnostics`](@ref) for acceptance and HMC warnings;
- [`mcmc_diagnostics`](@ref) for parameter-level R-hat and ESS;
- [`parameter_block_diagnostics`](@ref) for block-level summaries;
- [`diagnostics`](@ref) for the compact overall status;
- prior and posterior predictive checks, calibration, and sensitivity results.

Very short chains commonly produce unreliable R-hat and ESS values even when
the example completes without an exception.

[`fit_metadata`](@ref) and [`diagnostics`](@ref) retain their complete existing
payload with the default `view = :full`. For a reader-facing structured result,
request `view = :public`. The public form identifies its schema, model family,
and stability level in a compact portable payload. Experimental fit metadata
reports the fitted configuration as `estimation_status = :experimental`.
Public generalized diagnostics retain raw-space, constrained-space, and
combined convergence metrics, parameter names, and scientific warning counts,
while omitting initialization identity hashes and repository artifact paths.
The public form is intended for tables and reports, while the full form remains
available when the complete fitting record is required.

## Experimental Generalized Fitting

Generalized fitting is deliberately outside this stable fitting surface. Use
the [Experimental Generalized Models](experimental.md) page for the scalar
rater-consistency GMFRM and fixed-Q confirmatory MGMFRM contracts, examples,
and migration guidance.

Both configurations require `thresholds = :partial_credit`.
Both configurations require no anchors and no fitted DFF terms. Scalar GMFRM
uses `discrimination = :rater`; fixed-Q MGMFRM uses the compatibility selector
`discrimination = :none`. Use
`BayesianMGMFRM.Experimental.GeneralizedPrior` to vary the independent normal
scales on raw unconstrained coordinates. Direct-scale generalized priors remain
unsupported. Run `BayesianMGMFRM.Experimental.prior_predictive_check` before
fitting to inspect score, category-use, and facet-range implications.
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
when cache identity is explicitly part of the workflow. The compatibility
default `view = :full` is the complete reproduction archive and can contain
repository- and environment-specific metadata; use
`fit_artifact(fit; view = :public)` when
sharing a reader-facing artifact. The same distinction applies to
[`model_manifest`](@ref) and [`fit_reproduction_manifest`](@ref): retain the
full view for a private reproduction record and request `view = :public` for a
portable public projection. A cache hit should be accepted only when model,
data, prior, initialization, backend, and sampler controls match the requested
fit.

The same optional view is available for
[`sensitivity_comparison_summary`](@ref),
[`comparison_evidence_summary`](@ref), [`benchmark_summary`](@ref),
[`simulation_grid`](@ref), [`simulation_grid_summary`](@ref), and
[`falsification_rule_summary`](@ref). Their public projections retain the
scientific results in compact reader-facing payloads; the default full payload
remains unchanged.

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
