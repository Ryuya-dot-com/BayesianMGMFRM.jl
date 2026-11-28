# Development Roadmap

The aim is a reproducible path from a rating question to an explicit model,
an adequately precise estimate, interpretable uncertainty and fit, and saved
results that can be reopened. Ordinary one-dimensional 1PL/MFRM and generalized
scalar models are primary routes; additional dimensions or rater mechanisms
need a substantive reason. The value sought is a coherent Julia analysis with
explicit assumptions, usable uncertainty, reusable outputs and efficient
computation at the precision the question requires.

This page describes the local development version. It does not promise release
dates or extend the operations in [Scope and Releases](scope.md). An implemented
feature, statistical evidence, supported operations and an installed release
are different things. No general speed advantage over other software is established.

## What is available, and what remains to establish

The table separates development outcomes from conditions that users must still
check in every analysis. The latter do not disappear when a software milestone
is complete. A valid outcome can include an uncertain or negative answer, but
an unimplemented operation or inadequate evidence for a promised claim remains
unfinished.

| User outcome | Available scope | Development completion condition | Continuing analysis limits |
| --- | --- | --- | --- |
| A complete analysis of people, items and raters | Documented isometric 1D `MRCML` (Bayesian NUTS and frequentist `MMLE`/`JMLE` with FACETS Table 7 reliability and exact `WHEXACT` ZSTD), scale-identified 1D `GMFRM` and 2D/3D `LKJ` `MGMFRM` (compensatory `:additive` and bottleneck `:softmin`), contrasts, `fair_average`, diagnostics, figures, reports and SHA-256 `PortableHandoff` reproduction across Julia and R (`fit_mgmfrm`). | Tie the selected source and model/prior/backend roster to the necessary environment and saved-format evidence, collaborator reproduction and resolved workflow blockers. | Model adequacy, prior justification and numerical precision must be assessed for the supplied data. Available operations differ between model families. |
| Compare declared slopes or dimensions | Bounded fixed/free-slope and D1/D2 heldout comparison workflows are complete for their recorded targets. Selected external-software comparisons also exist. | Reuse these completed operations; further comparison requires a specific unmet question and an eligible common target or evaluation task. | No automatic winner, general selection accuracy or software-equivalence guarantee follows. |
| Plan a rating allocation | Separate fixed-truth and joint-prior SBC operations connect generation, fitting, full failure accounting, summaries and saved reproduction; bounded teaching studies are complete. | Complete independent workflow acceptance and the advertised environment/compatibility requirements for the declared planning route. Any retained performance claim needs its matching evidence. | The supplied generating model and decision target determine the answer. No universal calibration, allocation ranking or design assurance is established. |
| Analyse a declared composition of five or more fitted facets | Separate [user-named additive scalar facets](additive-facets.md), shared-response, paired ordinal, [star-factorized multi-criterion](star-association.md), [concurrent three-outcome](concurrent-three-outcome.md), rater-item and observed-group severity routes exist; they are not a general unrestricted composition interface. | Complete one declared composition's likelihood, identification, priors, independent checks, public fitting/prediction/report/save path and claim-appropriate evidence. | Metadata columns are not fitted effects. Prediction for new responses and a group-effect interpretation need their own assumptions; a group difference alone does not establish unfairness. |
| Estimate correlations among three constructs | [Correlated3D](correlated-3d.md) connects the bounded target to generation, retained-chain fitting, named correlations/covariance, conditional row probabilities and native restoration. | Establish claim-appropriate evidence across the stated domain, including sparse/weak-information and calibration requirements; one operation example is insufficient. | More dimensions, learned Q, cross-loadings and combinations with rater mechanisms are separate scopes. A fitted correlation does not establish construct validity. |
| Reproduce the selected empirical applications | Bounded contest, speech and image-rating analyses and saved-result assessments exist; some use private research models. | Complete the promised application's exact model and public operations, justified prior, fit/sensitivity and focal-precision assessment, and interpretable reproducible answer. Reuse completed fits. | Misfit and unresolved sensitivity limit conclusions. A private research fit is not an available public model combination; warnings alone do not satisfy a missing substantive claim. |
| Assess criterion discrimination loss | A criterion-collapse mixture provides fitting, class/category summaries, precision, figures and saving; a bounded category-use comparison is complete. | Complete replicated classification/prior evidence, remaining grouped predictive/comparison operations and independent acceptance for the declared scalar mechanism. | Good sampling or fitted category-count agreement does not identify a mechanism. Signed halo/horns and general impressions are not implemented or implied. |
| Assess temporal rater severity | A separate scalar RW1 route provides fitting, interpretation, static comparison and saved reproduction. | Complete the declared trajectory/recovery or prediction evidence, prior-sensitivity and precision requirements, and independent workflow acceptance. | Linking and time units matter. A trajectory is not an intervention effect; forecasting or combined halo/drift needs a separate model and evidence. |

## Priorities and completion criteria

The first finish is an accepted foundation for the declared existing workflows.
The wider planned product also includes the bounded capability and application
outcomes above. Completing the foundation does not complete those branches;
completing every branch is not a prerequisite for the first foundation delivery.

1. **Consolidate the unified `0.2` analysis and persistence surface.** Keep one
   coherent source, manual, and standalone R bridge connecting isometric
   one-dimensional `MRCML` (Bayesian NUTS and frequentist `MMLE`/`JMLE`),
   four-mode anchor equating, Plausible Values, group-impact DFF, scale-identified
   `GMFRM` and `LKJ`-correlated `MGMFRM` (compensatory `:additive` and smooth
   bottleneck `:softmin`), shared-event dependence, design-matrix/connectedness
   audits, and SHA-256 `PortableHandoff` reproduction. Statistical scope remains
   bounded to tested regimes and does not imply universal interval calibration in
   sparse or weakly linked designs.
2. **Complete independent collaborator reproduction and finalize scope.** An
   independent collaborator reproduces the documented workflows from clean
   Julia and R installations, inspects diagnostics and warnings, and verifies
   that permitted conclusions match the underlying evidence without mid-stream
   interface churn.
3. **Deliver the verified cross-platform package and manual.** Verify clean
   installation (including pinned remote R setup), startup, estimation,
   reporting, plotting, and save/reopen paths across supported operating systems
   and Julia LTS/current releases, alongside changelog and migration guidance.
   A passing local build alone does not complete this delivery step.
4. **Advance specialized capability and empirical branches on their own gates.**
   Multi-panel allocation planning, three-dimensional correlation recovery,
   bottleneck vs. compensatory rubric selection, criterion-collapse
   classification, temporal severity trajectories (`RW1`), and empirical
   applications advance through their own prospective accuracy and model-adequacy
   requirements rather than blocking foundation delivery.

A demonstrated mathematical, data-preservation or required-operation defect
takes priority in the affected route. Preserve valid estimates and rerun only
missing or invalidated work. Performance work should address a measured cost in
the selected operation at useful precision. Numerical convergence cannot repair
model misfit, and a faster gradient alone does not establish a faster analysis.

The [learning guide](learning-guide.md), [saved comparison workflow](common_prediction_comparison.md)
and [reproduction guide](api-saved-reporting.md#saved-result-reproduction) supply
existing operations. [Scope and Releases](scope.md) defines acceptance conditions.
Signed halo/horns, general impressions, exploratory structures and arbitrary
combinations remain conditional research directions, not additions to the
bounded completion criteria above.

## Existing comparison evidence and its limits

The four native ConQuest ordinary/category-use fits are complete. The
[worked comparison](migration-facets-conquest.md#fitted-category-counts)
explains their fitted-count identity, inconclusive AIC advantage and different
uncertainty treatment. Report the observed discrepancy even when collapse-class
support is low; these controls do not establish recovery of the target mechanism
or classification performance. Exact native mixture/prior parity remains
unverified, not disproved. This completed comparison informs interpretation;
it is not the next development milestone or a reason to launch a larger grid.

Selected Chopin posterior summaries have been compared with directly written
Stan and brms specifications; a separate observed-group severity comparison
uses direct Stan. These are model-specific checks, not general equivalence.
brms and direct Stan are two specification routes using the same Stan engine.
Numerical agreement does not remove the applications' misfit or sensitivity,
and differing timing scopes do not establish a general speed ranking.

The ConQuest binary-Rasch check uses a comparison-specific Julia prior adapter;
it does not verify the public PCM prior or criterion-collapse mixture. The
separate native category-use comparison uses MML, with fixed global estimates
for its conditional predictive calculation. It does not integrate parameter
uncertainty in the same way as the saved Julia Bayesian predictions. The
study-specific inputs and execution environments are not bundled by this page.
For an analysis, use the documented model/backend operations rather than assuming
that a general comparison launcher is available.

An **identical-posterior check** must match likelihood, scale, joint prior and
reported quantities. A **comparison of competing analyses** may use different
models, priors or estimators, but must state those differences and preserve a
common question. Plug-in fitted values, posterior intervals and predictive
tails are not interchangeable; neither are MML information criteria and Bayesian
evidence. Model-family overlap, numerical agreement, statistical calibration
and practical usefulness are different claims. Apply the same evidence standard
to this package and external software.

For claim-specific requirements, see [Evidence for Model Extensions](mgmfrm-research-roadmap.md).
For current operations, use [Scope and Releases](scope.md) and
[Contributing and reproduction](contributing.md).
