# Model Equations

`BayesianMGMFRM.jl` keeps model-equation metadata separate from fitting
availability. The [`model_equation`](@ref) contract records the intended family,
category kernel, primary-source references, required parameter blocks,
identification restrictions, implementation gaps, and whether a specification is
fit-ready.

The current public fitting surface is the minimal MFRM/RSM/PCM slice plus
guarded experimental generalized candidates: the scalar rater-consistency
GMFRM path and the fixed-Q confirmatory MGMFRM path with `dimensions >= 2`.
Broader GMFRM/MGMFRM specifications expose source-aligned manifests and preview
compiler rows for review, while broad generalized fitting remains guarded or
under development as described in [Scope and Releases](scope.md).

## Source Map

- Partial-credit lineage: Masters (1982), DOI
  [`10.1007/BF02296272`](https://doi.org/10.1007/BF02296272).
- Rating-scale lineage: Andrich (1978), DOI
  [`10.1007/BF02293814`](https://doi.org/10.1007/BF02293814).
- Generalized MFRM target: Uto and Ueno (2020), DOI
  [`10.1007/s41237-020-00115-7`](https://doi.org/10.1007/s41237-020-00115-7).
- Multidimensional generalized MFRM target: Uto (2021), DOI
  [`10.1007/s41237-021-00144-w`](https://doi.org/10.1007/s41237-021-00144-w).

See [API](api.md) for the rendered [`model_equation`](@ref) docstring.

## Generalized Partial-Credit and Multidimensional Structure

The guarded MGMFRM kernel follows the conditional response form in Uto (2021):

```math
P(Y_{pir}=k \mid \boldsymbol{\theta}_p)
\propto
\exp\left\{
\sum_{m=1}^{k} 1.7\,\alpha_r
\left(
\sum_{\ell=1}^{L}\alpha_{i\ell}\theta_{p\ell}
-\beta_i-\beta_r-d_{im}
\right)
\right\}.
```

This is an adjacent-category cumulative-softmax, or GPCM-form, kernel. There is
no integral over ability inside the conditional response probability. The
package samples person abilities as explicit posterior parameters. Integrating
other parameters out of a marginal posterior conceptually, or approximating a
posterior marginal with HMC draws, is a different operation from defining the
response function.

Uto (2021) describes the multidimensional GPCM basis and proposed MGMFRM as
*non-compensatory*. At the same time, the displayed predictor aggregates active
dimensions through the additive weighted sum
`sum_l alpha[i,l] * theta[p,l]`. Because the source label and the algebraic form
answer different questions, package contracts should record them separately.
The package should not silently relabel the source model as compensatory, nor
claim that it is operationally non-compensatory without a declared response-
surface criterion.

The present fixed-Q restriction gives these structural cases:

| Q structure | Meaning | Current status |
| --- | --- | --- |
| Exactly one active dimension in every item row | Between-item multidimensionality | Executable in the guarded fixed-Q branch when the remaining design checks pass. |
| Multiple active dimensions in at least one item row | Within-item multidimensionality for those items | Fixed confirmatory cross-loadings are executable but warning-bearing; they are not exploratory loadings. |
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

The current `q_matrix_validation` already distinguishes simple structure from
fixed cross-loadings and records pure-item support. It does not yet expose the
between-item/within-item/mixed taxonomy as one explicit model-family contract;
that is the bounded Stage 0 roadmap task.

Step sharing is not generated once for every facet:

| Family | Category kernel | Step ownership and sharing |
| --- | --- | --- |
| Stable MFRM/RSM | Rating-scale PCM form | One shared step vector across items and raters. |
| Stable MFRM/PCM | Partial-credit form | Item-specific step vectors shared across raters. |
| Guarded scalar GMFRM | Generalized partial-credit form with item discrimination and rater consistency | Rater-specific step vectors shared across items and persons. |
| Guarded fixed-Q MGMFRM | Multidimensional generalized partial-credit form with item-dimension discrimination and rater consistency | Item-specific step vectors shared across raters and dimensions. |

Consequently, adding a new facet does not automatically increase the number of
step vectors. Arbitrary facet-specific, nested, crossed, or partially pooled
step structures require a new likelihood, identification rule, prior, and
reporting contract.

## Independent Known-Truth Ordinal Kernel

The LD1a simulation API deliberately does not call the fitted probability or
likelihood implementation. For row `i`, category `0` has log weight zero and
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
Individual LD1a scenarios activate only their declared components. The
zero/near-zero/small/moderate/large scales are study-local inputs, not model
defaults or universal practical thresholds. This independent data-generating
equation is generator evidence only; repeated LD1b calibration and every
fitted clustered-effect equation remain future gates.

Every generated row is sampled independently after conditioning on the full
recorded truth. This differs from the baseline MFRM assumption: omitting a
shared testlet, halo, or second-dimension component leaves shared latent
variation, whereas rater-by-task and sequence terms misspecify the baseline
mean structure. Generated bundles report these cases separately through
`baseline_mfrm_assumption_status` instead of an unqualified global-local-
independence boolean.
