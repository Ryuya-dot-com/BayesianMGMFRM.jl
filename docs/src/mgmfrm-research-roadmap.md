# Evidence for Model Extensions

A new model option needs a defined measurement question, not just an additional
parameter. For existing functionality, use [Scope and Releases](scope.md),
[model equations](model-equations.md) and the [experimental guide](experimental.md).
This page describes evidence requirements, not results from completed studies.

## Start from existing explanations

Specify the user's question and the mechanism suggested by prior research, then
check which established models and software already address it. An unavailable
mapping in this package or an unverified external configuration is not evidence
that the capability is new. A useful implementation can contribute explicit
priors, joint uncertainty, interpretable output and measured efficiency without
claiming a new statistical model.

For rater effects, keep criterion discrimination loss, general impressions,
positive/negative spillover, overall severity and central category preference
distinct. [Jin and Chiu (2022)](https://doi.org/10.3758/s13428-021-01721-3) and
[Jin and Eckes (2025)](https://doi.org/10.3758/s13428-025-02667-6) motivate specific
mixture mechanisms; the current [criterion-collapse implementation](criterion-collapse.md)
does not implement all of them. ConQuest's documented
[rater/criterion and step models](https://conquestmanual.acer.org/s2-00.html#the-analysis-of-rater-effects)
are relevant alternative explanations, not proof of the same latent mixture.

## Match the question, model and evidence

| Question | Required specification and evidence |
| --- | --- |
| One or several latent dimensions? | Define the constructs and Q matrix. Compare models on the same observations, categories and prediction task, with explicit scale and prior conventions. |
| Fixed or estimated item/rater slopes? | State which term each slope multiplies. Check identification and comparable priors before interpreting a predictive difference as evidence for a slope policy. |
| Correlated dimensions? | Use a valid joint correlation construction and proper prior; identify marginal versus partial correlations. Check the full generation/fitting/reporting workflow and draw-wise uncertainty. A valid LKJ transform alone does not establish a reliable fitted model. |
| Repeated or clustered ratings? | Define the produced response, observation and shared effect. Distinguish prediction for an existing response from integration over a new response. Conditional row independence is an assumption, not an empirical conclusion. |
| More raters, items or shared ratings? | Define focal estimands, allocation, missing categories and failed analyses. Evaluate bias, error, interval coverage/width, availability and computational uncertainty under the proposed design. |
| Better diagnostics or practical decisions? | Establish the diagnostic's estimand and applicability. Investigate calibration and competing mechanisms before adopting a cutoff, classification rule or interpretation. |
| Halo, horns or another rating pattern? | Define which mechanism and direction are claimed. Compare ordinary ratings, the proposed mechanism and plausible adverse explanations. High criterion correlations, low within-person variation or rater severity alone do not identify the cause. An ordinary/centrality pair checks false attribution and adequacy under alternatives; it does not establish recovery when the target mechanism is present or general halo/horns classification. |

## Use the appropriate validation target

An **implementation comparison** must match the likelihood, categories, scale,
joint prior, conditioning and numerical precision. A **comparison of competing
analyses** can use different models, priors or estimators, but must preserve the
question and evaluation target, explain those differences and use comparable
outputs. The latter cannot be reported as an identical-posterior check. An
unresolved exact prior mapping does not prevent every useful model comparison.

Keep in-sample adequacy, prediction for unused observations and mechanism
identification separate. Increased flexibility can improve fitted patterns
without improving future prediction. State whether a discrepancy was selected
after seeing the data; a descriptive predictive tail is not automatically a
calibrated rejection threshold. For classification claims, include the target
mechanism and relevant alternatives, with replication and uncertainty appropriate
to sensitivity and false attribution. Such evidence is necessary for that
stronger claim, not a prerequisite for every descriptive comparison.

Check whether the estimating equations already force agreement on the chosen
summary. In the [native category-use example](migration-facets-conquest.md#fitted-category-counts),
matching rater category counts demonstrates representational capability; it is
not independent validation. Preserve conditional response variation and shared
effects, and distinguish fixed global estimates from joint posterior uncertainty
before comparing predictive summaries across estimators.

An experimental implementation can be part of gathering evidence. Separate its
mathematical/operational checks from support for a substantive or performance
claim; do not require a complete validation study before any prototype can exist.

Deterministic algebra and cross-implementation checks establish agreement for
the tested equations and coordinates. Posterior diagnostics address sampling
quality; they do not establish model adequacy. Parameter recovery studies use
known generating values, while simulation-based calibration averages over the
specified prior-generating distribution. Assurance additionally requires a
scientifically justified generating distribution and a decision rule.

Include weak-information and relevant misspecification cases when the intended
claim depends on them. Preserve rejected designs, failed fits and unavailable
quantities in the study denominator. Report replication uncertainty separately
from MCMC uncertainty. Select numerical accuracy requirements for the decision
being studied, rather than treating any completed computation as sufficient.

## Reproducibility

Use a fixed study specification, source/environment identifiers, explicit seed
rules and saved outcomes. Historical studies require their matching source and
evidence archive; this current overview is not their protocol. See
[Contributing and reproduction](contributing.md) and the
[development roadmap](roadmap.md). Completing one bounded check does not close
the larger research question or automatically commission another experiment.
