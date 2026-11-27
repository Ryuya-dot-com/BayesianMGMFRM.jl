# BayesianMGMFRM.jl

[![CI](https://github.com/Ryuya-dot-com/BayesianMGMFRM.jl/actions/workflows/CI.yml/badge.svg)](https://github.com/Ryuya-dot-com/BayesianMGMFRM.jl/actions/workflows/CI.yml)

**Estimate person ability, task difficulty and rater severity, with Bayesian uncertainty.**

When judges score a performance, a low score can reflect the performance, the
task or the judge's severity. BayesianMGMFRM.jl models these influences together.
Start with one-dimensional many-facet Rasch measurement (MFRM).

## Start here

**[Your First Rating Analysis](docs/src/first-analysis.md)** answers one question:
*is R2 more severe than R1?* Follow the supplied ratings, one analysis, its
figures and the meaning of the result. You can read it without running Julia.

![Isometric rater severities and joint R2 minus R1 posterior contrast](docs/src/assets/first-analysis-v02/posterior.png)

*Estimated from artificial teaching data under the standard `0.2.0-DEV`
isometric 1D partial-credit MFRM (`prior = :default`). Left: posterior medians
and central 90% credible intervals for all three raters on the zero-sum
isometric scale (every rater has quantified uncertainty without pinning `R1 = 0`).
Right: joint posterior draws of `R2 − R1` (mean `0.132` logit, median `0.141`
logit, 90% interval `[−0.499, 0.746]`). The interval spans zero, so these
ratings do not clearly establish which rater is more severe under this model
and prior; they do not prove equivalence.*

To run the example, follow [installation](docs/src/installation.md), then return
to the tutorial. This source and manual are package **0.2.0-DEV (unreleased)**
for Julia 1.10.8 or newer. Install from the matching `0.2.0-DEV` source tree
rather than older `0.1.x` snapshots; this is not a stable release.

## After the first analysis

- [Use your own ratings](docs/src/data-validation.md#import-csv) with the [recommended isometric 1D specification (`prior = :default`)](docs/src/first-analysis.md#recommended-standard-specification).
- [Fit Bayesian and frequentist MFRM, GMFRM, and scale-identified MGMFRM models from R](interfaces/R/BayesianMGMFRM/README.md) with `posterior` draws, covariances, contrasts, diagnostics, and portable JSON handoffs.
- [Choose a figure](docs/src/visualization-gallery.md) for a supported fitted model.
- [Find a recipe](docs/src/examples.md), a [function](docs/src/api.md), or the [Stan and brms migration guide](docs/src/migration-stan-brms.md).
- [Check available models and operations](docs/src/scope.md), including the
  design requirements for generalized, multidimensional and multi-outcome models.
- [Get help](docs/src/contributing.md) if an operation fails.

## Citation and license

Cite the exact software snapshot and the model references used in your analysis:
see [CITATION.cff](CITATION.cff) and [citation guidance](docs/src/registration.md).
MIT License; see [LICENSE](LICENSE).
