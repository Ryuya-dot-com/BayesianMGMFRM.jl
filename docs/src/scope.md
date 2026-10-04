# Scope and Releases

`BayesianMGMFRM.jl` follows a conservative release policy: a model family is
documented as supported only when its likelihood, parameterization, fitting
path, diagnostics, and user-facing examples are covered together.

## Current Support

| Model surface | Status | Notes |
|:--|:--|:--|
| One-dimensional MFRM with rating-scale or partial-credit steps | Supported | Available through the documented design, fitting, diagnostic, and reporting workflow. |
| Fixed-coefficient multidimensional MFRM | Experimental | `Experimental.fit` on Julia or CmdStan; fixed Q coefficients, unit logits and identity latent correlation. Manual caches and report/figure bundles are available. |
| Two-dimensional correlated MFRM | Experimental | `Experimental.correlated(spec)` then `Experimental.fit`; between-item fixed Q, at least two pure items per dimension and both dimensions observed for each person. Julia/CmdStan, manual caches and report/figure bundles are available. |
| Scalar GMFRM: item discrimination × rater consistency | Experimental | Enter through `BayesianMGMFRM.Experimental`; the documented structural restrictions remain mandatory. |
| Fixed-Q confirmatory MGMFRM | Experimental | Enter through `BayesianMGMFRM.Experimental`; at least two dimensions, a fixed Q mask, estimated positive active loadings and rater consistency, and independent ability priors. |
| Two-dimensional correlated MGMFRM | Experimental | Between-item Q, estimated positive loadings/consistency, `Experimental.correlated(spec)` and explicit `GeneralizedPrior`. Julia/CmdStan, prior/conditional posterior prediction, summaries, MCSE, diagnostics, manual caches and report/figure bundles are available. Scientific prior/domain acceptance remains open. |
| Broader generalized discrimination structures | Not supported | No stable fitting claim is made. |
| Exploratory loading patterns or higher-dimensional correlation estimation | Not supported for fitting | MGMFRM retains a fixed Q pattern and independent abilities unless explicitly wrapped for the admitted 2D correlation model. Both correlated models above require exactly two dimensions. |
| Group and differential facet functioning effects | Not supported for fitting | Design validation may describe these terms, but estimation is not yet exposed. |
| Testlet, response-cluster, and rater-halo effects | Not supported for fitting | Explicit identifiers, structural checks, and residual/predictive summaries are available. These report-only summaries provide no calibrated decision or mechanism classification. |

Experimental features may change in a minor release and should be
used with sensitivity checks. They must not be described as stable equivalents
of external software or as evidence for broader MGMFRM support.
The namespace is an explicit experimental stability boundary, not a maturity claim.
`BayesianMGMFRM.Experimental.surface_contract()` records its exact current
configurations and constraints. The historical `experimental = true` keyword is a
compatibility route and does not define the forward-looking API.

## What Changes When You Choose MGMFRM

Suppose several raters score responses on criteria intended to measure two
abilities. The analysis must separate ability differences from item difficulty
and rater severity. A fixed-coefficient multidimensional MFRM assigns each
active item-dimension link a coefficient of one. MGMFRM additionally estimates
how strongly each active dimension affects an item's ratings and how sharply
each rater's category probabilities concentrate. Choose between these models
according to that question and the rating design; the additional parameters
are assumptions to investigate, not an automatic improvement.

For the independent fixed-Q MGMFRM:

| Component | Estimated or specified? | Interpretation |
|:--|:--|:--|
| Q pattern and active loadings | The zero/nonzero pattern is supplied; each active positive loading is estimated. | Fixed Q does **not** mean fixed coefficients. A zero excludes a dimension from that item. Multiple active dimensions enter an additive weighted sum. |
| Abilities and item difficulties | Person abilities and item difficulties are estimated; the ability prior mean is zero and `person_sd` is supplied. | The prior SD is not estimated population variability or an individual's posterior uncertainty. Separate ability/item locations depend on the declared priors. |
| Rater severity and consistency | Both are estimated subject to zero-sum severity and product-one consistency constraints. | Severity shifts the rating distribution. Consistency multiplies the category logits; larger values concentrate probability around the most favored category or tied categories, holding other parameters fixed. It is not a test-retest reliability coefficient or a measure of accuracy against an external standard. |
| Category steps | Free item-specific steps are estimated; the baseline step is zero and the last nonbaseline step is reconstructed to make their sum zero. | Category use can differ by item. The steps for an item are shared across raters and dimensions. |
| Dependence between dimensions | Ability prior correlation is fixed to identity. | This is a population-prior assumption, not a finding that posterior estimates or observed scores are independent. Estimating correlation requires the separate admitted two-dimensional correlated model. |

The response multiplier is fixed at `1.7` in MGMFRM; fixed-coefficient MFRM uses
unit logits. Raw ability or difficulty estimates from the two models therefore
cannot be compared as though the scale and prior were unchanged. The
[equations](model-equations.md#Generalized-Partial-Credit-and-Multidimensional-Structure)
and [experimental guide](experimental.md#Workflow) give the parameter and prior
conventions. In particular, the compatibility value `discrimination = :none`
does not disable the estimated loadings in an MGMFRM specification.

Read constraints together with priors. With more than two raters, equal SDs on
free coordinates in the current MGMFRM prior do not give every constrained
rater the same marginal prior. The last sorted rater is reconstructed from the others; changing which
rater occupies that position can change the prior and posterior. Likewise,
finite posterior intervals for separate ability and item locations do not
establish likelihood identification. The [location explanation](experimental.md#Location-diagnostics-for-fixed-Q-MGMFRM)
shows which joint shift leaves rating probabilities unchanged and how to inspect
its mixing without changing the model.

## Interpreting Support and Versions

“Supported” describes the documented implementation boundary, not proof of
convergence or validity for a new dataset. Experimental availability does not
establish recovery, robustness, or external-software agreement. Known-truth
simulation and protocol helpers have their own [research API
reference](api-validation-evidence.md); their presence does not change the
fitting boundary above.

The registered release remains the default installation. Development versions
may contain unreleased behavior and should be pinned to an explicit revision
when used in reproducible work.

Read the manual and examples for the installed revision. Development
documentation can describe features absent from an earlier registered release.
