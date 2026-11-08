# Paired ordinal ratings with event association

Use `BayesianMGMFRM.Experimental.JointRatings.OrdinalAssociation` to describe
two ordinal traits measured on the same productions, while separating variation
between persons, between productions, and within an assessment event. For
example, multiple listeners rate a recording for accentedness and
comprehensibility. A recording is a response; one listener assessing it is an
event. Repeated listeners do not become additional independent speakers.

This is an opt-in Experimental model with unit coefficients, explicit criterion
means, estimated person SDs and a common ordinal association parameter. It is
separate from the [fixed-person-SD JointRatings model](joint-ratings.md).
No scientific default prior, general construct-validation claim or causal
interpretation is supplied. Its first pronunciation application retains
joint/grouped misfit and unassessed prior sensitivity despite adequate numerical
precision. A numerically successful fit can be substantively inadequate.

## Specify the observations and priors

Use the [JointRatings input schema](joint-ratings.md): `observation_id`,
`person`, `task`, `response_id`, `rating_event_id`, `rater`, `criterion`, and
integer raw `score`. IDs are exact nonempty strings. Each criterion declares its
full increasing integer `levels`, `direction` and `threshold_group`. Use two
distinct threshold groups and a common number of at least three categories.
Omit a missing rating; its partner remains in the likelihood. Both criteria
must occur for each person, and at least two persons, tasks and raters are
required. These structural checks do not establish statistical identification.

```julia
using BayesianMGMFRM
const A = BayesianMGMFRM.Experimental.JointRatings.OrdinalAssociation

# Illustrative working prior, not a recommended default. Choose and assess it
# for your population, design, category support and substantive question.
prior = (
    task_sd=1.5, rater_sd=(1.0, 1.0), step_sd=(1.0, 1.0),
    response_log_sd_mean=(log(.5), log(.5)), response_log_sd_sd=(.5, .5),
    person_lkj_eta=2.0, response_lkj_eta=2.0,
    intercept_sd=1.5, person_log_sd_mean=log(.5), person_log_sd_sd=.5,
    lambda_sd=.5,
)
target = A.model(rows; criteria, prior)
A.contract()
```

Criterion-specific vectors follow sorted criterion IDs; step SDs follow sorted
threshold-group IDs. Task, rater and step effects use orthonormal sum-zero
contrasts. Their declared SDs describe contrast coordinates, not the marginal
SD of every centered effect. Person effects have a zero **population** mean;
their realized sample mean is uncertain. Independent criterion means have
Normal(0, `intercept_sd`²) priors. Person and response log SDs have the specified
normal priors; both correlation matrices have the specified LKJ priors. Lambda
has a Normal(0, `lambda_sd`²) prior. There is no silently inserted intercept,
predictor, freely estimated slope or rater-specific lambda.

Before relying on results, examine the implications of these priors, fit and
sensitivity for your application. The package's structural and numerical checks
do not supply that assessment. Large repeated-rating counts cannot compensate
for a small number of persons when interpreting population covariance.

## Fit and preserve the uncertainty

```julia
result = A.fit(target; ndraws=4000, warmup=1500, chains=4,
    seed=7281, reconstruction_seed=7282, target_accept=.95,
    max_depth=12, metric=:diagonal)
save_fit("paired-ordinal.jls", result)
```

Calling `fit` starts sampling; constructing `model` does not. Counts above are
illustrative, not a guarantee of adequate precision. The analytic gradient
feeds AdvancedHMC. Threaded chains can be selected with
`chain_execution=:threads, max_parallel_chains=4` in a process with enough
Julia threads. No automatic continuation or fit-cache lookup occurs. There is
no public CmdStan sampling backend for this route; independent fixed-point
Stan checks do not constitute a posterior or speed comparison.

Sampling integrates the common person-mean/intercept decomposition exactly.
For each retained joint state, `fit` draws two independent conditional white
coordinates using `reconstruction_seed` and stores them. They restore the
uncertainty in person profiles and criterion means. Saving or reloading never
replaces them with conditional expectations or regenerates them. All parameters,
chain/iteration ordering, warmup telemetry and warnings are retained together.

Native `.jls` files are trusted-input files requiring their producing source,
Julia and Project/Manifest environment. Do not load untrusted native files.
A newer source is not automatically compatible. An audited migration must check
the original source, joint pairing and reconstructed effects; it is separate
from ordinary `load_result`. JSON reports do not contain a replayable posterior.
Existing paths are not overwritten.

## Reopen, report and interpret

```julia
saved = load_fit("paired-ordinal.jls")
summary = posterior_summary(saved; interval=.95)
save_report("paired-summary.json", summary)

# Use your exact stored criterion and person IDs.
difference = A.contrast(saved; facet=:person, criterion="Accentedness",
    left="speaker:201", right="speaker:202", interval=.95)
save_report("speaker-difference.json", difference)
```

Reports retain model/prior metadata and contextual warnings. Default summaries
cover person profiles, criterion means, person/response SDs and the four
association quantities below. Exact names in `summary.result.parameter_names`
can be selected with `parameters=[...]`. All raw, model and conditional-location
diagnostics remain even when fewer parameters are summarized. Check R-hat,
bulk/tail ESS, retained divergences, energy diagnostics, warmup warnings and
the MCSE of both means and interval endpoints. Focal precision is explicitly
unassessed until compared against the precision required by your decision.
Intervals are equal-tailed credible intervals, not HDIs or raw-score intervals.

| Reported quantity | Interpretation |
| --- | --- |
| `rho_person` | Model population correlation between the two person effects; depends on the population model and prior. |
| `centered_profile_correlation` | Correlation across the observed persons' latent profiles in each joint draw; a finite-sample description. |
| `rho_response` | Correlation between produced-response effects after adjusting for person, task and rater effects. |
| `lambda` | Conditional adjacent log odds ratio between the two ordinal scores within an event; not a Pearson correlation. |

A person contrast compares the same trait across two persons. Positive values
mean more of the canonical trait; raw-score direction is retained. Positive
rater contrasts mean greater severity. Contrasting one person's accentedness
against their comprehensibility as if they were the same scale is unsupported.
Differences between raw-score correlation and `rho_person` are differences in
estimands, not evidence that one number corrects the other.

For one existing event, inspect the full conditional table:

```julia
joint = A.event_probabilities(saved; rating_event_id="your-event-id")
save_report("event-probabilities.json", joint)
```

The table supplies original raw labels, intervals and MCSE. It conditions on
fitted effects and includes both margins even for a singleton observation.
These probabilities are not heldout performance estimates or new-person
predictions. Positive probability mass is not evidence against a zero effect.
There is no automatic adequacy decision. The existing application's joint and
rater-group discrepancies remain a reason to limit interpretation, not a reason
to declare a psychological mechanism or automatically select a richer model.

## Model and numerical reference

For canonical scores k,l=0,…,K−1, c=(K−1)/2 and criterion-specific adjacent
logit sums U, the normalized table is

```math
p(k,l\mid\cdot)=\frac{\exp\{U_1(k)+U_2(l)+\lambda(k-c)(l-c)\}}
{\sum_{a=0}^{K-1}\sum_{b=0}^{K-1}\exp\{U_1(a)+U_2(b)+\lambda(a-c)(b-c)\}}.
```

Each location is criterion mean + person − task − rater + response effect.
The association term follows the fixed-score uniform-association construction
described by [Goodman (1979)](https://doi.org/10.1080/01621459.1979.10481650).
Its combination with these hierarchies and priors is this model's specification,
not a prior recommendation by that paper. Lambda=0 gives conditional
independence. Nonzero lambda changes the margins; this is not a copula preserving
the independent PCM margins. Missing partners are marginalized from the same
joint table under an ignorable-missingness assumption.

The selected nine-category model has independent normalized-density and gradient
agreement with a complete Stan reference at finite points, and preserves an
existing four-chain Julia analysis through an audited saved-result transfer.
This is implementation evidence, not general recovery, SBC, prior robustness,
independent scientific acceptance, Stan posterior agreement or ConQuest native
equivalence. Three-category deterministic/sampler checks establish a separate
small operation test, not additional empirical validation.

## Help

```@docs
BayesianMGMFRM.Experimental.JointRatings.OrdinalAssociation.contract
BayesianMGMFRM.Experimental.JointRatings.OrdinalAssociation.model
BayesianMGMFRM.Experimental.JointRatings.OrdinalAssociation.fit
BayesianMGMFRM.Experimental.JointRatings.OrdinalAssociation.report
BayesianMGMFRM.Experimental.JointRatings.OrdinalAssociation.contrast
BayesianMGMFRM.Experimental.JointRatings.OrdinalAssociation.event_probabilities
BayesianMGMFRM.Experimental.JointRatings.OrdinalAssociation.save_result
BayesianMGMFRM.Experimental.JointRatings.OrdinalAssociation.load_result
BayesianMGMFRM.Experimental.JointRatings.OrdinalAssociation.save_report
```
