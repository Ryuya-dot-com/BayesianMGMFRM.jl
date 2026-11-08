# Star-Factorized Multi-Criterion Ordinal Association

!!! note "Unreleased documentation preview — 30 October 2026"
    This manual includes unreleased interfaces and examples. It is not the
    documentation of an installed release. Model support and scientific
    acceptance remain as stated on each page.

When raters evaluate each performance or entity across $D \ge 2$ criteria that
may have **different numbers of score categories** ($K_c \ge 2$, including
mixed ordinal and binary criteria), `BayesianMGMFRM.Experimental.StarAssociation`
(or `BayesianMGMFRM.Experimental.joint_rating_spec(...; association = :star)`)
estimates:

1. **Correlated multidimensional entity abilities and rater severities** under
   zero-sum orthonormal Helmert bases and rowwise `LKJCholesky` correlation
   priors with log-normal marginal scale priors.
2. **Criterion-specific partial-credit thresholds** (`K_c - 1` sum-to-zero steps
   per criterion) and explicit criterion intercepts.
3. **Within-event residual star association** ($\phi_{0c}$) around a declared
   root criterion ($c = 0$), reducing exact event-table normalization from
   $\prod_{c=0}^{D-1} K_c$ cells to $K_0 \bigl(1 + \sum_{c=1}^{D-1} K_c\bigr)$
   operations per rating event while retaining exact analytical gradients.
4. **Optional unit-Jacobian reference-profile prior transport** on the root
   criterion margin when `reference_prior = true`.

## Parameterization, numerical defaults and their limits

Unbalanced multi-facet rating designs often combine heavily observed panel
raters or entities with sparsely observed ones. By default:

- `ParameterizationConfig()` orders facet levels by descending observation count
  (`basis_order = :descending_schur`) and uses a dimensionless working-information
  rule (`entity_mode = :cp_ncp`, `rater_mode = :cp_ncp`, cutoff `8.0`) to choose
  centered or standardized noncentered contrast coordinates.
- Fitting uses independent dispersed initialization (`init = :overdispersed`),
  Stan-style three-stage windowed adaptation (`adaptation = :stan`) and a diagonal
  reference approximation based on design counts and prior scales
  (`initial_metric = :prior_fisher`). The metric does not use observed scores.

These choices are motivated by centered/noncentered theory and bounded engineering
checks. They are not a proof of optimal NUTS mixing or scientific prior defaults.
In particular, [Papaspiliopoulos, Roberts and Sköld (2007)](https://arxiv.org/pdf/0708.3797)
explain complementary parametrizations and partial noncentering; they do not
derive the package's PCM/NUTS cutoff of eight. Select priors for the application
and inspect both whole-fit diagnostics and focal mean/interval Monte Carlo error.

### Exact identities and working approximations

For a single Gaussian working facet with positive count weights
``W=\operatorname{diag}(c)``, total ``N=\sum c_i`` and an orthonormal sum-zero
basis ``H``, the Schur identity is

```math
\{H^\top(W-cc^\top/N)H\}^{-1}=H^\top W^{-1}H.
```

The reciprocal diagonal defines the effective counts used here. Sorted counts
make these values invariant to relabeling and isolate the most observed levels
in early contrasts. This identity does not give the full crossed ordinal model's
marginal posterior curvature: the other facet, thresholds, scales, correlations
and within-event association also matter.

At a reference PCM profile, the exact natural-parameter information is the score
variance. With maximum canonical score ``m=K-1``, the implementation uses

```math
\widetilde{\mathcal I}
=\min\{\max[\operatorname{Var}_{p^{(0)}}(Y),10^{-6}],m(m+2)/12\},
\qquad
\kappa_j=e^{2\mu_{\log\sigma}}\min_{c}\widetilde{\mathcal I}_{c}\,n_{\mathrm{eff},j}.
```

Binary support uses `0.25`. The upper bound is the uniform-profile variance,
not the largest possible variance on the support. Negative step spacing can
activate that cap; concentrated profiles can activate the floor. The scale is
the squared prior median SD, not the prior mean variance. Thus this is a routing
proxy, not exact posterior information. Contrasts with ``\kappa_j\ge8`` use CP;
others use NCP. The cutoff, clipping and diagonal initial metric remain disclosed
engineering choices. They retain their bounded stress-test support; they do not
establish efficiency for all sparse designs, scales or associations.

The exact target density, CP/NCP transformations and Jacobians are separate from
this routing choice. Changing coordinates must preserve the physical likelihood
and joint prior. The Glass-Box functions below expose those identities. Choosing
a different coordinate partition is not a change to the scientific model.

### Step-size search and failures

For `adaptation=:stan`, a finite positive step size returned by the initial search
is used without an extra package floor/cap. A nonfinite/nonpositive search result
raises an error; it is not replaced by a seemingly successful fixed step. Inspect
the initial state, prior scales and metric before retrying. An explicit
`step_size` is validated and used as requested. The opt-in
`adaptation=:clamped_regularized` still applies its declared bounds and records a
warning. Removing a silent fallback does not establish posterior qualification;
the normal diagnostic and focal-precision requirements remain.

## What qualification covers

`qualify(fitted; max_rhat=1.01, min_ess=400.0, min_bfmi=0.3)` checks all raw and
transformed coordinates and every retained sampler record. The original names
`rhat_max`, `ess_min`, and `ebfmi_min` remain aliases; do not pass both spellings.
A partial check with `check_transformed=false` reports the omitted gate as missing
and cannot return whole-fit or overall qualification.

The additional focal gates apply only to `result.focal_parameters`: the finite
entity correlations `cor_entity_direct[branch]`, pairing each branch with the root.
The default MCSE limits are 0.01 for the mean and 0.02 for the 2.5%/97.5% interval
endpoints. They do not qualify all population correlations, residual associations,
contrasts, ranks or predicted event probabilities. Those require their own
reported MCSE and a justified precision criterion. Changing the graph root also
changes this focal list. Passing these numerical gates does not establish prior
adequacy, fit, identification or scientific validity; source warnings remain.

## Unified Practitioner Workflow Example

The bundled example supplies 36 artificial ratings (four entities, three raters,
three criteria) and all nine required prior settings. These values demonstrate
the interface; they are not a sample-size recommendation or scientific defaults.
Choose and assess priors for your application before substantive analysis.

```julia
using BayesianMGMFRM
include(joinpath(pkgdir(BayesianMGMFRM), "examples", "star_association.jl"))
prepared = StarAssociationExample.inputs()  # No fitting or simulated ratings.
spec = prepared.spec
summary_info = design_summary(spec)
```

For your own data, each row needs `observation_id`, `rating_event_id`, `entity`,
`rater`, `criterion`, and `score`. Each complete event contains one row per
criterion. Criterion specifications use `criterion` and `levels`, with one
`role = :root`. Inspect `prepared.rows`, `prepared.criterion_specs` and
`prepared.prior` for a complete example. Name the specifications
`criterion_specs` so they do not shadow the `criteria` function.

The following operations generate prior values or ratings; keep their seed:

```julia
q_raw = prior_draw(spec; seed = 42)
synthetic = simulate(spec; seed = 42)
```

This block **runs four chains**. If you already have a saved fit from the matching
source and environment, use the reopening block instead. Short artificial examples
may fail precision gates; preserve those warnings rather than treating completion
of sampling as numerical qualification.

```julia
result = fit(spec; ndraws = 500, warmup = 500, chains = 4, seed = 20261030)
out = mktempdir(mkpath("results/star-analysis"); cleanup = false)
fit_path = joinpath(out, "star-fit.jls")
save_fit(fit_path, result)
answer = StarAssociationExample.result(result)
answer.gate.result.numerically_qualified
answer.posterior
answer.difference
save_report(joinpath(out, "star-summary.json"), answer.posterior)
```

The helper also returns entity summaries, finite-cohort reliability, ranks,
classification probabilities, and event-level WAIC/PSIS-LOO. Inspect the
qualification and criterion warnings before interpreting them. Numerical
qualification does not establish prior adequacy or model fit.

Use `prior_sensitivity(result, alternative_prior)` or a vector of named prior
alternatives to inspect focal changes while preserving physical coordinates.
Each alternative must specify a complete prior, as required by `PriorConfig`.
An exactly identical resolved prior returns `status = :unchanged_prior`: the
baseline empirical distribution is reused and mean shifts are exactly zero.
`pareto_k`, `r_eff` and `psis_n_eff` are `nothing` (JSON `null`) because no
importance-sampling adjustment is needed. The existing `alt_psis_*` field names
are retained; their quantiles use the weighted empirical CDF. This status does
not certify convergence or prior adequacy, and does not erase sampling warnings
or posterior uncertainty. Focal MCMC MCSE is not computed by this sensitivity
report. Constant weights under a different prior do not receive this exemption.
Saved reports retain their original contents; native fits must still be opened
with their producer source and environment.

To compare two fitted Star models, use the shared entry point:

```julia
comparison = compare_models("association" => result, "no_residual_association" => no_residual_result)
comparison.primary_name
comparison.baseline_name
comparison.waic_diff
comparison.psis_loo_diff
comparison.any_sampling_warning
```

`no_residual_result` must be an already fitted alternative on the same observed
events. Event order is aligned by ID; scores, actual entity/rater labels,
criterion IDs, category supports and scoring directions must match. Different
priors, roots and residual association terms remain valid model differences.
With `include_phi=false`, residual association is fixed to zero while entity/rater
correlations remain estimated. Both criteria use complete events, not individual criterion ratings. The first
model is the primary model; differences are primary minus baseline without an
automatic ranking. Current in-memory `criteria(fit)` results can be compared without recalculating
the likelihood. Older records without observed-event identity are refused for
comparison, while their saved reports remain readable.

SEs retain the existing entity + rater - observation variance approximation
and observation-variance floor. The output identifies clipping and repeated
entity/rater pairs; the latter lack an intersection-cluster adjustment. These
SEs are not MCMC MCSE or a general calibration guarantee. See the
[comparison and prediction-unit guide](bayesian-workflow.md#6.-Compare-Models-Carefully).

Reopen the saved analysis without refitting:

```julia
reloaded = load_fit(fit_path)
reopened_answer = StarAssociationExample.result(reloaded)
```

Optional figures require `using CairoMakie` and are called with
`BayesianMGMFRM.plot(result; kind = :posterior)`, `:diagnostics`, or `:predictive`.
The predictive figure generates replicated category counts from **all retained
draws**, conditional on the fitted entities and raters. It displays observed and
expected proportions with 95% replicated intervals, separately by criterion;
these are predictive intervals, not credible intervals for the expected rates.
Use `seed` to reproduce this check. Figure notes are printed outside the image.

## Glass-Box Researcher Inspection

Methodological researchers can inspect exact basis partitions, coordinate
diffeomorphisms, triangular change-of-variables Jacobians, analytical gradients,
and Stan data dictionaries directly:

```julia
ebasis = facet_basis(spec, :entity)
coords = coordinates(spec, q_raw)
q_ncp = to_ncp_reference(spec, q_raw)
log_jac = log_jacobian_to_ncp(spec, q_raw)
lp, grad = logdensity_and_gradient(spec, q_raw)
sdata = stan_data(spec)
```

## Reference

```@docs
BayesianMGMFRM.Experimental.StarAssociation
BayesianMGMFRM.Experimental.StarAssociation.contract
BayesianMGMFRM.Experimental.StarAssociation.FacetBasis
BayesianMGMFRM.Experimental.StarAssociation.validate_design
BayesianMGMFRM.Experimental.StarAssociation.prior_draw
BayesianMGMFRM.Experimental.StarAssociation.simulate
BayesianMGMFRM.Experimental.StarAssociation.prior_predictive_check
BayesianMGMFRM.Experimental.StarAssociation.fit
BayesianMGMFRM.Experimental.StarAssociation.qualify
BayesianMGMFRM.Experimental.StarAssociation.posterior_summary
BayesianMGMFRM.Experimental.StarAssociation.facet_summary
BayesianMGMFRM.Experimental.StarAssociation.category_summary
BayesianMGMFRM.Experimental.StarAssociation.reliability
BayesianMGMFRM.Experimental.StarAssociation.ranking
BayesianMGMFRM.Experimental.StarAssociation.classification
BayesianMGMFRM.Experimental.StarAssociation.waic
BayesianMGMFRM.Experimental.StarAssociation.psis_loo
BayesianMGMFRM.Experimental.StarAssociation.criteria
BayesianMGMFRM.Experimental.StarAssociation.predictive_check
BayesianMGMFRM.Experimental.StarAssociation.compare_models
BayesianMGMFRM.Experimental.StarAssociation.prior_sensitivity
BayesianMGMFRM.Experimental.StarAssociation.evaluate
BayesianMGMFRM.Experimental.StarAssociation.save_fit
BayesianMGMFRM.Experimental.StarAssociation.load_fit
BayesianMGMFRM.Experimental.StarAssociation.parameter_names
BayesianMGMFRM.Experimental.StarAssociation.facet_basis
BayesianMGMFRM.Experimental.StarAssociation.coordinates
BayesianMGMFRM.Experimental.StarAssociation.reparameterize_point
BayesianMGMFRM.Experimental.StarAssociation.reparameterize_draws
BayesianMGMFRM.Experimental.StarAssociation.logprior
BayesianMGMFRM.Experimental.StarAssociation.loglikelihood
BayesianMGMFRM.Experimental.StarAssociation.pointwise_loglikelihood
BayesianMGMFRM.Experimental.StarAssociation.logposterior
BayesianMGMFRM.Experimental.StarAssociation.logdensity_and_gradient
BayesianMGMFRM.Experimental.StarAssociation.stan_data
BayesianMGMFRM.Experimental.StarAssociation.sampler_controls
```
