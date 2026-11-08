# Model Equations

!!! note "Unreleased documentation preview — 13 October 2026"
    This manual includes unreleased interfaces and examples. It is not the
    documentation of an installed release. Model support and scientific
    acceptance remain as stated on each page.

For a first explanation with a worked three-category example, read
[How Rating Models Work](rating-model-theory.md). This page gives the more
detailed mathematical and source conventions.

`BayesianMGMFRM.jl` keeps model-equation metadata separate from fitting
availability. The [`model_equation`](@ref) contract records the intended family,
category kernel, primary-source references, required parameter blocks,
identification restrictions, implementation gaps, and whether a specification is
fit-ready. `fit_ready` describes the stable compiler route;
`experimental_fit_available` separately identifies an executable generalized
configuration.

Fitting supports one-dimensional MFRM/RSM/PCM, experimental fixed-coefficient
multidimensional MFRM, scalar GMFRM with item discrimination × rater consistency,
and fixed-Q confirmatory MGMFRM with `dimensions >= 1`. Fixed-coefficient MFRM
uses independent abilities by default; `Experimental.correlated(spec)` explicitly
selects population correlation for two between-item dimensions. See
[Correlated ability dimensions](experimental.md#Correlated-ability-dimensions)
for its priors, coordinate transformation and fitting constraints.
The [route-specific conventions](#Fixed-coefficient-routes-and-their-priors)
distinguish scalar MFRM from the fixed-Q routes. For independent/correlated
multidimensional MFRM, [prior scales and facet labels](@ref "Prior scales, facet labels and locations")
explain its reconstructed rater/step distributions and prior-anchored locations.
Broader GMFRM/MGMFRM specifications expose source-aligned manifests and preview
compiler rows for review. Only the restricted generalized configurations in
[Scope and Releases](scope.md) can be fitted.

## Source Map

- Partial-credit lineage: Masters (1982), DOI
  [`10.1007/BF02296272`](https://doi.org/10.1007/BF02296272).
- Rating-scale lineage: Andrich (1978), DOI
  [`10.1007/BF02293814`](https://doi.org/10.1007/BF02293814).
- Generalized MFRM target: Uto and Ueno (2020), DOI
  [`10.1007/s41237-020-00115-7`](https://doi.org/10.1007/s41237-020-00115-7).
- Multidimensional generalized MFRM target: Uto (2021), DOI
  [`10.1007/s41237-021-00144-w`](https://doi.org/10.1007/s41237-021-00144-w).

The [`model_family_contract`](@ref) complements this equation manifest.
Calling it without an argument returns the family skeleton; calling it with a
specification or design returns the exact category kernel, multidimensional
structure, aggregation rule, loading policy, step owner, latent-correlation
policy, identification status, and fitting boundary for that object.

```julia
contract = model_family_contract(spec)
contract.dimensionality.classification
contract.steps.owner
contract.support.implementation_status
```

See [API](api.md) for the rendered [`model_equation`](@ref) and
[`model_family_contract`](@ref) docstrings.

## Fixed-coefficient routes and their priors

With categories indexed ``0,\ldots,K-1``, the scalar unit-logit PCM uses

```math
\log\frac{P(Y_{pir}=k)}{P(Y_{pir}=k-1)}
=\theta_p-b_i-s_r-d_{ik},\qquad k=1,\ldots,K-1.
```

Its K-1 transition offsets sum to zero within each item. RSM instead shares
one such vector across items. In generalized implementation arrays, an extra
leading zero marks the baseline log weight; it is not a second transition.
Thus binary responses have one transition offset, fixed to zero, and no free
step parameter. For K>2 there are K-2 free offsets in each centered vector.

These routes must be distinguished before assigning priors:

| Route | Location and step conventions without user hard anchors | Prior meaning |
| --- | --- | --- |
| Stable scalar `family=:mfrm`, `MFRMPrior` | First item and rater levels fixed at zero; person locations free; shared RSM or item-owned PCM steps sum to zero. | Independent zero-centered normals on free coordinates. Fixed reference coordinates have no prior density. The final step is minus the sum of the free steps. |
| Fixed-coefficient multidimensional MFRM, `MFRMPrior` | Active Q coefficients one; rater severities sum to zero; item and person locations prior-anchored; item-owned PCM steps. | Independent free-coordinate normals, including R-1 free severities. The reconstructed rater and step need not have the same variance as free entries. |
| The preceding route with `Experimental.ExchangeablePrior` | Same likelihood and constraints. | A normalized exchangeable centered rater prior replaces the free-rater prior. Item, ability and free-step priors retain their previous meanings. |
| D1 `Experimental.slope_restriction` with both slope types `:fixed_one` and exchangeable `NormalizedMGMFRMPrior`, optionally `MeanProfilePrior` | Rater severities and item-owned steps sum to zero; item and person locations remain free; the raw response equation retains 1.7. | Centered exchangeable normal rater and step residuals; independent person/item normals. Mean profiles add fixed item/step means. This prior is distinct from scalar `MFRMPrior`. |

For the last route, set ``\widetilde\theta=1.7\theta``,
``\widetilde b=1.7b``, ``\widetilde s=1.7s`` and
``\widetilde d=1.7d`` to obtain the unit-logit equation above. Transform the
prior means and SDs at the same time. `MeanProfilePrior(units=:unit_logit)`
converts its supplied means only; the base-prior SDs still use raw units.
This conversion is specific to this fixed-one D1 route, not a rule to multiply
every generalized-model parameter by 1.7.

For this route, ``\theta_p-b_i`` is invariant when all person and item
locations are shifted together. The proper priors determine their separate
positions along that likelihood-invariant direction. With J persons, R raters,
I items and item-owned PCM steps, there are ``J+(R-1)+I+I(K-2)`` free parameters.
The ordinary scalar route instead has ``J+(R-1)+(I-1)+I(K-2)``. An extra free
item location does not make the conditional response family multidimensional.

Hard anchors replace the relevant scalar reference convention; they are fixed
values, not uncertain measurements. Re-expressing samples in a centered gauge
does not replace their original prior with an exchangeable prior. A same-target
software comparison must match the induced joint prior, not just this response
equation or the names of the constraints.

The scalar default reference is the first level in the stored label order, not
the first input row. Inspect `data.rater_levels`, `data.item_levels` and the
display of `spec`. Reordering rows preserves those levels; renaming IDs can
change which physical rater/item is the reference. With `r1=0` and independent
`r2,r3 ~ Normal(0,sigma)`, the prior variances of `r2-r1` and `r2-r3` are
`sigma^2` and `2sigma^2`. This is a particular prior on contrasts, not a neutral
choice for interchangeable raters. Scalar fit reports retain this caveat in
their fixed-coordinate warnings; it is a model-interpretation warning, not a
failed convergence diagnostic. A lone fixed facet, including `rater=nothing`,
does not create free within-facet contrasts.

Changing references preserves the same posterior only when the full probability
model is transported, including abilities, priors and any absolute cut scores.
Simply reusing the SD keywords after relabeling is a new prior specification.
See [Comparing fit and decisions](migration-facets-conquest.md#Comparing-fit-and-decisions)
for analysis selection and the distinction between transformed samples and a refit.

## Generalized Partial-Credit and Multidimensional Structure

The guarded scalar GMFRM kernel follows Uto and Ueno (2020), Eq. 9. Its
multiplier is `alpha_i * alpha_r`; that original equation does not include a
fixed `1.7` factor. Uto (2021), Eq. 4 restates the scalar model with `1.7`,
whereas the multidimensional Eq. 6 below also uses `1.7`. The implementation
keeps the original 2020 scalar convention and the 2021 multidimensional
convention explicit in `category.source_scale_contract`. Direct numerical
comparison of discrimination parameters across those families therefore
requires a predeclared scale harmonization rather than an implicit comparison.

### Read model parameters and effective slopes

For a fitted scalar GMFRM, fixed-Q MGMFRM, normalized-prior MGMFRM (including
the D1 slope restriction), or correlated-2D MGMFRM, choose the quantity explicitly:

```julia
model_parameters = posterior_summary(result; scale=:model)
raw_coordinates = posterior_summary(result; scale=:raw)
slopes = posterior_summary(result; estimand=:adjacent_logit_slope)
slope_precision = posterior_mcse(result; estimand=:adjacent_logit_slope)
```

The no-keyword summary retains its historical raw-coordinate meaning.
`scale=:model` equals the existing qualified `direct_posterior_summary(result)`;
it does not absorb the fixed response multiplier into loadings or consistency.
The direct parameter list retains its existing scope; reconstructed category
steps are also available in model-coordinate report/plot views.

The slope rows describe `a_i*c_r` for scalar GMFRM and `1.7*a_id*c_r` for MGMFRM.
They differentiate the **adjacent-category log odds** with respect to one unit
of the named ability, holding other ability components fixed. Each product is
computed within a stored joint draw, so its mean/interval is not a product of
separate marginal means/intervals. These slopes are not reliability coefficients,
standardized effects or cumulative-event log odds. They include structural Q
zeros and explicitly fixed coefficients; a constant estimated trace does not
become a fixed parameter. Rows flag item-rater pairs without direct observations.
For model comparisons, align ability units, constructs and conditioning as well
as the response units. Scale conversion alone does not match joint priors.

To retain these quantities and their endpoint MCSE in the shared report:

```julia
report = fit_report(result; include_effective_slopes=true,
    include_posterior_predictive=false, include_waic=false, include_loo=false)
save_report("model-report.json", report)
restored = load_report("model-report.json")
```

This report option uses all retained draws and no predictive RNG. The derived
section retains the report's whole-fit diagnostics and prior context; available
MCSE does not certify convergence or scientific precision. The raw/model selector
and slope estimand above do not extend the separate Correlated3D record API or
other joint/association models. Their existing report behavior is preserved.

The related constants `1.7` and `1.702` have different contractual roles.
`1.702` is the conventional minimax scaling constant used to approximate a
normal-ogive response curve with a logistic curve; `1.7` is its commonly
rounded form and is the literal value printed in Uto (2021), Eqs. 4 and 6.
Consequently, the source-reproduction likelihood uses exactly `1.7`, not
`1.702`. The family contract records `1.702` only as
`normal_ogive_minimax_reference_constant`. Changing the executable constant
would define a new likelihood version and require regenerated reference
results; it is not a numerical-precision correction to the current source
model.

The guarded MGMFRM kernel follows the conditional response form in Uto (2021),
written here with zero-based category index k and an empty sum for k=0:

```math
P(Y_{pir}=k \mid \boldsymbol{\theta}_{p})
\propto
\exp\left\{
\sum_{m=1}^{k} 1.7\,\alpha_r
\left(
\sum_{\ell=1}^{L}\alpha_{i\ell}\theta_{p\ell}
-\beta_i-\beta_r-d_{im}
\right)
\right\}.
```

This accumulates adjacent-category log odds and then applies softmax, giving
a GPCM-form kernel; it does not use cumulative-event odds ``P(Y\geq k)/P(Y<k)``. There is
no integral over ability inside the conditional response probability. The
package samples person abilities as explicit posterior parameters. Integrating
other parameters out of a marginal posterior conceptually, or approximating a
posterior marginal with HMC draws, is a different operation from defining the
response function.

Uto (2021) describes the multidimensional GPCM basis and proposed MGMFRM as
*non-compensatory*. At the same time, the displayed predictor aggregates active
dimensions through the additive weighted sum
`sum_l alpha[i,l] * theta[p,l]`. The package records the source label separately from the algebra. On a
cross-loaded item, an increase in one ability can offset a decrease in another
while preserving the weighted sum and category probabilities; see the
[worked conditional comparison](experimental.md#Dimension-aggregation-and-item-structure).
No alternative conjunctive or product-of-dimension response kernel is fitted.

The present fixed-Q restriction gives these structural cases:

| Q structure | Meaning | Current status |
| --- | --- | --- |
| One Q column, active for every item | Unidimensional restriction of the MGMFRM kernel | Executable with an explicit one-column Q; not the scalar rater-step GMFRM. |
| Two or more Q columns, exactly one active dimension in every item row | Between-item multidimensionality | Executable in the guarded fixed-Q branch when the remaining design checks pass. |
| Multiple active dimensions in at least one item row | Within-item multidimensionality for those items | A fixed confirmatory zero mask with estimated positive active loadings is executable but warning-bearing; it is not exploratory loading selection. |
| Both single-dimension and cross-loaded item rows | Mixed between-/within-item structure | Representable through fixed Q, subject to Q rank, person support, pure-item, and connectivity review. |
| Dense or freely estimated item-dimension structure as in the unrestricted source parameterization | Every `alpha[i,l]` is potentially estimated without a fixed zero mask | Not implemented by the guarded fit. |
| Conjunctive, product, minimum, or another non-additive dimension rule | A separate operationally non-compensatory response function | Not implemented. |

Uto's Eq. 6 assigns an `alpha[i,l]` parameter to each item-dimension pair and
therefore describes an unrestricted, within-item-capable loading surface rather
than a between-item Q design. The guarded package branch deliberately masks
some loadings to zero with a fixed Q. An all-active mask is not automatically a
valid substitute: the current validator also requires distinguishable Q columns
and adequate identification/design support. The guarded branch is therefore a
restricted Uto-equation candidate, not the complete source loading model.

The [`model_family_contract`](@ref) now exposes this taxonomy directly as
`:unidimensional`, `:between_item`, `:within_item`, or `:mixed_between_and_within_item`, while
`q_matrix_validation` continues to record the lower-level Q rank, person
support, pure-item, and connectivity evidence. A missing Q is rejected during
specification construction; an empty-row Q is rejected by validation and is
never classified as a valid multidimensional structure.

Step sharing is not generated once for every facet:

| Family | Category kernel | Step ownership and sharing |
| --- | --- | --- |
| Stable MFRM/RSM | Rating-scale PCM form | One shared step vector across items and raters. |
| Stable MFRM/PCM | Partial-credit form | Item-specific step vectors shared across raters. |
| Guarded scalar GMFRM | Generalized partial-credit form with item discrimination and rater consistency | Rater-specific step vectors shared across items and persons. |
| Guarded fixed-Q MGMFRM | One- or multidimensional generalized partial-credit form with item-dimension discrimination and rater consistency | Item-specific step vectors shared across raters and dimensions. |

Consequently, adding a new facet does not automatically increase the number of
step vectors. Arbitrary facet-specific, nested, crossed, or partially pooled
step structures require a new likelihood, identification rule, prior, and
reporting contract.

## One versus multiple dimensions under the same kernel

A useful comparison asks whether items need distinct ability dimensions while
keeping the response equation and prior conventions aligned. Set
`family=:mgmfrm, dimensions=1, q_matrix=trues(n_items,1)` for the explicit
one-dimensional restriction. It has adjacent-category log odds

```math
\log\frac{P(Y_{pir}=k)}{P(Y_{pir}=k-1)}
=1.7\,\alpha_r(\alpha_i\theta_p-\beta_i-\beta_r-d_{ik}).
```

This is **not** the package's scalar `family=:gmfrm` equation, whose log odds
are `alpha_i * alpha_r * (theta_p - beta_i - beta_r - d_rk)`.
Besides the fixed 1.7 multiplier, the models differ in step owner and whether
item discrimination multiplies locations and steps. Comparing those two named
families is possible, but does not isolate dimensionality.

The one-dimensional MGMFRM keeps positive item loadings, zero-sum rater
severities, product-one rater consistencies, item-owned zero-sum nonbaseline
steps and the same prior rules as its multidimensional counterpart. With K
categories each item has K-2 free steps. Ability origin and scale remain
prior-anchored; admitting one dimension is not a new likelihood-identification
constraint. Raw, normalized exchangeable and normalized source priors remain
explicit choices. The correlated wrapper still requires exactly two dimensions.

For a between-item comparison with one active loading per item, the loading
count and each parameter block's prior convention can be kept the same;
only the ability dimension structure and item assignment change. Cross-loaded
models also change the number and roles of loadings, so the example excludes
them. Equal numeric prior settings do not imply equal joint prior predictive
laws: sharing one ability or using independent dimension-specific abilities
changes dependence between item responses. This is not a nested comparison
obtained by fixing a supported correlation parameter to one.

See the [matched-dimension workflow](common_prediction_comparison.md#Matched-dimensionality-comparison)
for common training/held-out splits. The one-dimensional extension is an
implementation restriction of this equation, not a claim that the published
scalar GMFRM has been reproduced, or evidence of calibrated intervals or
reliable dimensionality selection.

## Estimands, origins and units

For fixed-Q MGMFRM, positive loadings specify orientation but do not by
themselves identify ability origins and units in the conditional response
model. Write the predictor as `a_i' theta_p - b_i`, with the prime here denoting
transpose. For arbitrary shifts `c_d` and positive scales `t_d`, the following
simultaneous change preserves every category probability:

```math
\theta^*_{pd}=t_d\theta_{pd}+c_d,\qquad
a^*_{id}=a_{id}/t_d,\qquad
b^{*}_{i}=b_i+\sum_d a_{id}c_d/t_d.
```

Rater severities, consistencies and item steps are unchanged. This preserves
the fixed zeros of Q, including mixed Q. The declared priors generally
distinguish the transformed parameters; the invariance is a likelihood
property, not equality of posterior targets with unchanged prior formulas.
The normal population ability prior fixes a distributional origin and unit;
it does not force the fitted persons' sample mean to zero or variance to one.

For pure-Q items i and j in the same dimension, this has concrete consequences:

| Quantity | Effect of the change | Interpretation |
| --- | --- | --- |
| Ability difference `theta_p - theta_q` | Multiplied by `t_d` | Sign and ordering are invariant; magnitude and nonzero practical-equivalence bounds require an ability unit. |
| Loading ratio `a_i/a_j` | Unchanged | Same-dimension relative sensitivity; cross-dimension ratios have separate units. |
| Item-location difference `b_i-b_j` | Adds `(a_i-a_j)c_d/t_d` | Generally origin-dependent, including its sign. |
| Difference `b_i/a_i-b_j/a_j` | Multiplied by `t_d` | Difference between centers in ability coordinates; sign is invariant but magnitude needs a unit. |
| Item location relative to the panel, `b_i-a_i*mean(theta_d)` | Unchanged | Refers to the same fitted-person panel; changing that panel changes the estimand. |
| Rater severity difference or consistency ratio | Unchanged | Conditional on the specified zero-sum/product-one constraints; this does not remove prior sensitivity or establish rating reliability. |
| Matched category probabilities | Unchanged | Person coordinates and item parameters must move together. |

For example, loadings `(0.8,1.6)` and item locations `(0.2,0.1)` give an
item-location difference of `0.1`. Shifting that ability dimension by one
changes the locations to `(1.0,1.7)`, and the difference to `-0.7`, with exactly
the same probabilities. A difference in b remains a valid estimand under a
declared population origin; it is not automatically an origin-free item
comparison. The existing [location diagnostics](experimental.md#Location-diagnostics-for-fixed-Q-MGMFRM)
already report panel-relative locations, using draw-specific loadings.

For a **complete crossed, pure-Q design**, with finite parameters, at least
one item per dimension and nonconstant person abilities in every dimension,
these location/positive-scale changes exhaust the conditional response
model's ambiguity. To see this, take adjacent log odds divided by 1.7. A
nonzero person difference is proportional to each rater's consistency; product
one fixes all consistencies. Dividing them out, then averaging with the
zero-sum rater and item-step constraints recovers severities, steps and the
person-item predictors. Within each dimension, person differences in these
predictors determine loadings and abilities up to a common positive scale;
their levels leave one origin. This argument uses the entire probability
table, not estimated cell frequencies from a single rating panel.

If all persons have the same ability in a dimension, an individual item's
loading and location can compensate each other, so even loading ratios need
not be identified. The completeness claim does not extend here to sparse or
cross-loaded designs, or to a model with abilities integrated out. Structural
Q checks and invariance of a selected contrast alone do not establish those
broader identifiability results or adequate finite-data precision.

For the first core candidate's proper normal raw prior and a finite set of
valid category observations, posterior existence follows separately: each
likelihood is strictly positive and at most one, so its prior integral is in
`(0,1]`. A normalized posterior therefore exists. This does not establish
numerical representability, MCMC convergence, recovery, calibration, or the
scientific appropriateness of the prior.

The [MGMFRM prior comparison](@ref "MGMFRM prior choice and comparable scales")
distinguishes the raw prior from explicit normalized priors, explains
their rater asymmetry and gives explicit scale-matching conventions.

## Density on free and constrained coordinates

An equality constraint reduces dimension. A zero-sum vector has no ordinary
n-dimensional density; the package records a density with respect to its n-1
independent coordinates. To see the distinction, let
``u=(z_1,\ldots,z_{n-1})`` and ``z_n=-\sum_{j<n}u_j`` for n>1.

For independent free-coordinate normals, the raw prior is

```math
p_{\mathrm{raw}}(u)
=(2\pi\sigma^2)^{-(n-1)/2}
\exp\left(-\frac{\sum_{j<n}u_j^2}{2\sigma^2}\right).
```

This is already normalized and proper. It gives the last effect variance
``(n-1)\sigma^2``, compared with ``\sigma^2`` for each free effect.

For the exchangeable centered prior with kernel SD ``\tau``, the full vector
has covariance ``\tau^2(I-\mathbf1\mathbf1^\top/n)``. Its density on the **same
free coordinates** is

```math
p_{\mathrm{centered}}(u)
=\frac{\sqrt n}{(2\pi\tau^2)^{(n-1)/2}}
\exp\left(-\frac{\sum_{j=1}^{n}z_j^2}{2\tau^2}\right).
```

The free-coordinate covariance is
``\tau^2(I_{n-1}-\mathbf1\mathbf1^\top/n)``, whose determinant is
``\tau^{2(n-1)}/n``. This gives the normalization above. Each full effect has
SD ``\tau\sqrt{(n-1)/n}``, and each pairwise difference has SD
``\sqrt2\tau``. The word *normalized* in the API does not mean that the raw
prior was improper. It names this explicitly normalized constrained-vector
law and its specified source variant.

Relative to independent free normals with SD ``\tau``, the log-density
correction is ``\frac12\log n-(\sum_{j<n}u_j)^2/(2\tau^2)``. Multiplying n
ordinary normal densities at the constrained vector without the normalization
does not give the displayed free-coordinate density. Fixed-scale constants
cancel in one posterior's normalization, but matter for density comparisons
and cannot be dropped when they depend on a parameter. If n=1 the sole effect
is fixed at zero and contributes no free-coordinate density.

For a fixed zero-sum mean profile m, apply the centered formula to ``z-m``.
Unequal means remove exchangeability of the full prior, while its residuals
remain exchangeable. Increasing means do not impose ordered sampled steps.

Deterministically reconstructing the last coordinate does not add another
Jacobian to these already-declared free-coordinate densities. A **change of
sampling coordinates** does: if ``v=f(u)`` is invertible, then
``p_v(v)=p_u(f^{-1}(v))\lvert\det Df^{-1}(v)\rvert``. For d free coordinates
all multiplied by a positive constant c, the log-density adjustment is
``-d\log c``. For ``a=\exp(z)``, it is ``-\log a`` when expressing a z-density
as an a-density. Transforming stored draws to compute summaries needs no such
weighting. See [Stan's change-of-variables discussion](https://mc-stan.org/docs/stan-users-guide/reparameterization.html#changes-of-variables).

### The two-dimensional LKJ transformation

For the supported two-dimensional correlation target, let
``B(a,b)=\int_0^1 t^{a-1}(1-t)^{b-1}\,dt``. The normalized LKJ marginal is

```math
p(\rho\mid\eta)=\frac{(1-\rho^2)^{\eta-1}}{B(1/2,\eta)},
\qquad -1<\rho<1.
```

With ``\rho=\tanh z``, the Jacobian contributes one more power of
``1-\rho^2``:

```math
\log p_z(z\mid\eta)
=\eta\log(1-\tanh^2 z)-\log B(1/2,\eta).
```

The ability normal density also depends on rho through its covariance
determinant and quadratic form; it is still required in the joint prior.
This is not a prescription to transform pairwise correlations independently
in dimension three or higher. The [correlation guide](experimental.md#Correlated-ability-dimensions)
states the supported designs and parameter restrictions; general LKJ/Cholesky
formulas do not extend that fitting boundary.

## Independent Known-Truth Ordinal Kernel

The research helper [`simulate_local_dependence`](@ref) does not call the
fitted probability or likelihood implementation. Its optional generating
effects below are not additional effects available through `fit`. For row `i`, category `0` has log weight zero and
the standalone adjacent-category recurrence is

```math
\ell_{i0}=0, \qquad
\ell_{ik}=\ell_{i,k-1}+\eta_i-\delta_{ik}, \qquad
P(Y_i=k)=\frac{\exp(\ell_{ik})}{\sum_h \exp(\ell_{ih})}.
```

The generating location records every additive component separately:

```math
\eta_i = A_{p[i],j[i]}-\beta_{j[i]}-\rho_{r[i]}
       +u_{p[i],t[i]}+h_{r[i],s[i]}-g_{r[i],t[i]}
       -d_{r[i]}z_i,
\qquad
A_{pj}=\sqrt{1-(\lambda q_{j2})^2}\,\theta^{(1)}_{p}
       +\lambda q_{j2}\theta^{(2)}_{p}.
```

Here the optional terms represent person-by-testlet variation, rater-response
halo, rater-by-task severity, an omitted second dimension, and sequence drift.
The omitted-dimension control crosses active and inactive items within every
testlet and uses the square-root weight above so its active-item latent variance
does not increase merely because a second independent ability was added.
Individual simulation scenarios activate only their declared components. The
zero/near-zero/small/moderate/large scales are study-local inputs, not model
defaults or universal practical thresholds. This independent data-generating
equation describes generated data only; it does not calibrate an observed-data
diagnostic or enable clustered effects in the fitted model.

Every generated row is sampled independently after conditioning on the full
recorded truth. This differs from the baseline MFRM assumption: omitting a
shared testlet, halo, or second-dimension component leaves shared latent
variation, whereas rater-by-task and sequence terms misspecify the baseline
mean structure. Generated bundles report these cases separately through
`baseline_mfrm_assumption_status` instead of an unqualified global-local-
independence boolean.
