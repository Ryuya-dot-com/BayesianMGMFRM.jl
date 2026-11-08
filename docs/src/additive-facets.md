# User-Named Additive Facets

!!! warning "Experimental scalar additive workflow"
    This route fits a scalar additive model with any number of user-named facets.
    Shared workflow verbs provide joint summaries, MCSE, known-level probabilities
    and save/reload. Numerical success does not establish scientific suitability
    or general calibration. Existing `mfrm_spec(::FacetData)` retains its priors.

## Choose effects by your question

Use this route when one stable ability is meant to explain ratings after
adjusting for several additive difficulties or severities. A facet name is a
label chosen by you: `assessor`, `session`, or `my_effect` has no special meaning
to the compiler. Adding an input column alone adds no effect. More facets do
not imply more latent dimensions or better measurement.

`facets` maps your effect names to your table's columns. `steps` selects a named
effect as step owner, or `:global` for shared rating-scale steps. No `criterion`,
`occasion`, `site` or `mode` keyword is required or supported on this route.

```julia
using BayesianMGMFRM

# Artificial complete allocation; these scores are placeholders, not evidence.
rows = collect(Iterators.product(1:3, 1:2, 1:2, 1:2, 1:2, 1:2, 1:2))[:]
ratings = (speaker=[x[1] for x in rows], judge=[x[2] for x in rows],
           task=[x[3] for x in rows], trait=[x[4] for x in rows],
           round=[x[5] for x in rows], room=[x[6] for x in rows],
           device=[x[7] for x in rows], score=[mod(i, 3) for i in eachindex(rows)])

options = (
    person=:speaker, score=:score, category_levels=0:2,
    facets=(assessor=:judge, prompt=:task, aspect=:trait,
            session=:round, venue=:room, medium=:device),
    steps=:aspect,
    prior_sd=(person=1.0,
              facets=(assessor=0.5, prompt=0.5, aspect=0.5,
                      session=0.5, venue=0.5, medium=0.5),
              step=0.5))
spec = mfrm_spec(ratings; options...)

design_summary(spec)             # Seven facets including the person role
contract(spec)                   # Scope, priors, coordinates and input record
q = prior_draw(spec; seed=41)     # One complete prior draw; no estimation
coordinates(spec, q)             # Reconstructed, labelled effects
p = predictive_probabilities(spec, q)  # Original-row probabilities at fixed q
sim = simulate(spec; seed=42)    # One joint prior-predictive dataset
```

The numbers above illustrate syntax, not recommended prior scales. Renaming
`aspect` to any admissible name and updating `steps` and its prior key leaves
the mathematical model unchanged. Each active facet needs an explicit positive
SD. The ability role and names `person`, `score`, `steps`, `global`, `performance`
and `assessment` are reserved to avoid ambiguous output/role declarations.
Duplicate effect columns and unknown/missing prior keys are errors.

## Mathematical meaning and units

For rating n and adjacent category k,

```math
\log\frac{P(Y_n=k)}{P(Y_n=k-1)}
 = \theta_{p(n)}-\sum_f b^{(f)}_{j_f(n)}-\tau_{g(n),k}.
```

The trait is scalar; coefficients and the logistic multiplier are fixed at one.
Higher facet effects mean harder/stricter conditions. Each facet and each step
vector sums to zero. Ability is not sample-centered. For a facet-owned step
vector, its mean effective step difficulty is that facet's location effect.
Steps need not be ordered. Binary categories have one fixed-zero step per group,
requiring `step=0`; a singleton facet likewise requires zero SD.

All supplied SDs describe reconstructed marginal effects. With m levels and an
orthonormal Helmert basis H, a facet uses
`b = sd * sqrt(m/(m-1)) * H*z`, with standard-normal z. This prior is exchangeable
over labels. It differs from independent normals on arbitrary dropped-level
coordinates and from the legacy reference-based MFRM prior. Step blocks use the
same construction; abilities are independent zero-mean normals with the supplied
person SD. Scales are fixed and no scientific defaults are supplied.

`parameter_names(spec)` lists white coordinates; `scale=:model` lists reconstructed
effects. `coordinates` includes the log-volume for the map from white coordinates
to orthonormal constraint-subspace volume. `logprior`, `pointwise_loglikelihood`,
`logposterior`, and `logdensity_and_gradient` expose normalized mathematical
calculations. `stan_data(spec)` exports the inputs to the independent equations
in `src/stan/additive_facets.stan`; it does not compile or run Stan. Its dense
reference matrices are for verification, not the production evaluation path.

## Check what your allocation can separate

Read `validate_design(spec)` and `design_summary(spec).allocation`. Rank uses
the observed sparse location design and the centered-step decomposition; it
does not construct the Cartesian product of all levels. The tolerance, missing
levels and dependent reference columns are reported. A dependent column names
one pivot choice, not the unique cause of confounding.

If every task is assigned to exactly one room, task and room may be inseparable.
A proper prior does not establish data identification. Such designs remain
inspectable and usable for prior simulation; `fit` refuses them. Full rank does
not demonstrate adequate information, correct dimensionality or suitable priors.
Absent observed score categories are reported in category counts and remain in
the declared support. Missing scores are errors, never recoded as zeros.

To retain the same panel across subsets, pass
`levels=(person=[...], facets=(assessor=[...], prompt=[...], ...))` with every
declared facet. Undeclared levels are errors. Dropping and recentering absent
levels would change the model and prior.

Optional `performance` and `assessment` column names retain grouping identities.
A performance belongs to one person, and an assessment belongs to one performance
when both IDs are supplied. Additional physical-task/rater/session semantics
must be validated for the application: arbitrary names do not convey them.
Identical rating profiles require distinct grouping identities to distinguish
legitimate repetitions from duplicate rows. IDs do not add residual dependence.

## Fit, assess precision and preserve the joint result

With real scores, fit the specification you inspected. For this artificial example,
use generated scores with the same declared model and prior:

```julia
demo = mfrm_spec(sim.simulated; options...)
result = fit(demo; ndraws=2000, warmup=1000, chains=4, seed=73)
sampler_controls(result)
diagnostics(result)             # All raw/model coordinates, sampler and warmup
quality = qualify(result)       # Whole-fit numerical gates, not model adequacy
posterior_summary(result)       # Labelled effects in unit logits
posterior_mcse(result)          # Mean and interval-endpoint Monte Carlo error
names = parameter_names(result)
BayesianMGMFRM.posterior_contrast(result; left=names[1], right=names[2]) # Joint-draw difference
pred = predictive_probabilities(result; rows=[1, 2])
report = fit_report(result)
save_fit("additive-fit.jls", result)
restored = load_fit("additive-fit.jls")
receipt = save_report("additive-report.json", report; return_receipt=true)
stored_report = load_report(receipt.path; expected_sha256=receipt.sha256)
```

Counts and seed are required. `target_accept=.9`, `max_depth=10`,
`step_size=.03`, `init_jitter=.1` and `metric=:diagonal` are sampler defaults;
analytic gradients and the existing NUTS adaptation are used. `progress`,
`chain_execution` and `max_parallel_chains` use the shared controls. There is no
automatic retry, extension or acceptance. A dependent design is rejected before
sampling. The artificial prior values and counts above are examples, not a
recommendation for an application.

`posterior_summary` accepts `scale=:raw` for white coordinates or `:model` for
unit-logit effects, `parameters` for exact names, and `interval` for an equal-tailed
credible interval. `posterior_mcse` uses the same scale/name selection and accepts
`probabilities` for the requested quantile endpoints. `fit_report` combines the
selected summary/MCSE with all-coordinate diagnostics, prior/constraint records,
controls and typed input-label encodings. Selecting a focal effect does not remove
whole-fit warnings. Fixed singleton effects and binary steps are marked fixed;
their zero MCSE is not evidence of estimated precision.

The default `qualify` gates require at least four chains, raw/model rank-normalized
Rhat <= 1.01, bulk/tail ESS >= 400, zero retained divergences, nonfinite densities
or maximum-depth hits, complete telemetry and each E-BFMI >= .30. Its scope is
whole-fit diagnostics. Focal precision remains separately unassessed until you
compare the reported MCSE to accuracy requirements in the units of your question.
A failed gate remains visible; scientific acceptance is never automatic.

`posterior_contrast` subtracts two exact model-parameter names within each saved
draw before computing its interval, MCSE and event probabilities. Interpret the
orientation from the selected parameters: higher ability is better, higher facet
effects are harder/stricter. Event probabilities are not multiplicity-controlled
or causal decisions. An unvarying event indicator has unavailable MCSE rather
than a proof that its probability is zero or one.

## Predict known levels and save without changing the panel

`predictive_probabilities(result; rows=[...])` integrates over the joint posterior.
It returns posterior mean category probabilities, intervals and MCSE for each
conditional category probability. These intervals describe uncertainty in the
probability, not an interval of observed scores; the mean probabilities are the
predictive categorical distribution. The method is deterministic and draws no
replicated outcomes.

Pass `data=new_rows` to predict different combinations of existing levels. Supply
the original person/facet/grouping columns; scores are unnecessary and ignored.
Only observed levels in the ORIGINAL declared panels are allowed. Their original
centering, prior and step ownership are preserved even when prediction includes
only one level. Unknown persons/facet levels are rejected. Grouping IDs are
retained and validated against stored performance/person and assessment/performance
links but do not introduce residual dependence. `rows` selects
rows of the supplied table. Memory holds model-coordinate draws and one row's
category probabilities at a time; requesting many rows increases calculation
and output costs. New-level prediction and arbitrary model combinations remain
outside this route.

Julia 1.12 native streams cannot be read by Julia 1.10. Retain the producing
environment for native samples and use JSON for portable computed reports.

Native saving refuses overwrites and retains complete chain/iteration order,
input/level/column identities, target and sample checksums, controls and producer
versions. Loading rechecks the target and every retained density using the
producing source and compatible dependency environment. Only load trusted Julia
native files. Cross-version or cross-OS native compatibility is not promised.
Portable JSON reports retain computed values, source identities, warnings and
typed label encodings; they are not posterior samples for further inference.
Keep the separately returned file digest to verify the exact portable artifact.

## Interpret generation and remaining limits

`simulate` uses one common parameter draw for a whole replicate, retaining all
selected columns and IDs. Supply `q` for a fixed-parameter replicate.
`prior_predictive_check(spec; ndraws=50, seed=1)` returns replicated category counts
and design warnings. Inspect plausibility for your application; the function
does not certify prior suitability, recovery or calibration.

The model assumes conditional independence given the declared effects. It has
no shared performance effect, halo or time process. An effect named `session`
is a static contrast, not learner growth or rater drift. The probability method
above conditions on fixed q and the original rows; it is not a posterior
predictive distribution. New-level prediction, interactions, mixed supports,
hard-anchor equating, multidimensional loadings and free slopes are not supported
by this compiler. Scientific recovery/calibration and practical model adoption
remain open. Model comparison, posterior replicated-outcome checks and new-level
prediction are not supplied by this bounded fitted workflow.
