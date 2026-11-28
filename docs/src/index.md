# BayesianMGMFRM.jl

Estimate person ability, task difficulty and rater severity together, with
uncertainty about their differences.

**[Start: Your First Rating Analysis](first-analysis.md)**

Is R2 more severe than R1? Follow one supplied dataset, the analysis and three
figures explaining its answer and checks. You can read the result without
running Julia. You do not need to study all the model families first.

## [Installation](@id Install-this-development-preview)

To run the tutorial, follow [installation](installation.md), then return to it.
This manual matches package **0.2.0-DEV (unreleased)** for Julia 1.10.8 or
newer. The installation guide covers the pinned Git revision and local source trees.

## [After the first analysis](@id find-by-task)

- [Prepare your own ratings](data-validation.md#import-csv).
- [Find a task recipe](examples.md) or [function reference](api.md).
- [Migrating from Stan and brms](migration-stan-brms.md) (`adapt_delta` / `target_accept`, `max_treedepth` / `max_depth`, `E-BFMI`, defaults and diagnostics) or [from FACETS and ConQuest](migration-facets-conquest.md).
- [Understand facets and model choices](learning-guide.md).
- [Check supported combinations](scope.md) before using an extension.
- [Get help with a failed operation](contributing.md).

## [Figures](@id visual-tour)

The tutorial explains one fitted result. For other views, use the
[visualization gallery](visualization-gallery.md), which separates illustration
data from estimated results and identifies the inputs each plot accepts.
