# How Rating Models Work

!!! note "Unreleased documentation preview — 13 October 2026"
    This manual includes unreleased interfaces and examples. It is not the
    documentation of an installed release. Model support and scientific
    acceptance remain as stated on each page.

A rating model assigns a probability to each possible score. Its parameters
describe how those probabilities change with the person, item and rater.
This page builds the equations from a three-category example, then explains
what generalization, multiple dimensions and Bayesian estimation add.
The notation follows the implemented families; the detailed
[Model Equations](model-equations.md) page records their source conventions.

## From adjacent categories to probabilities

Write ``Y_{pir}`` for the rating of person ``p`` on item ``i`` by rater ``r``.
Let its categories be ``0,\ldots,K-1``. For the partial-credit MFRM, define

```math
x_{pir}=\theta_p-b_i-s_r, \qquad
\log\frac{P(Y_{pir}=k)}{P(Y_{pir}=k-1)}=x_{pir}-d_{ik},
\quad k=1,\ldots,K-1.
```

| Symbol | Meaning | Effect when other parameters are held fixed |
| --- | --- | --- |
| ``\theta_p`` | Person ability | Larger values favor higher scores. |
| ``b_i`` | Item difficulty | Larger values favor lower scores. |
| ``s_r`` | Rater severity | Larger values favor lower scores. |
| ``d_{ik}`` | Step offset for the transition from category ``k-1`` to ``k`` | A larger offset makes that transition harder. |

The ratio compares two **adjacent exact categories**. It is not the odds of
scoring at least ``k``. At ``x_{pir}=d_{ik}``, categories ``k-1`` and ``k``
have equal probabilities, but either might be less probable than another category.

Recover all category probabilities by accumulating the adjacent log odds:

```math
\ell_0=0, \qquad
\ell_k=\sum_{m=1}^{k}(x_{pir}-d_{im}), \qquad
P(Y_{pir}=k)=\frac{\exp(\ell_k)}{\sum_{h=0}^{K-1}\exp(\ell_h)}.
```

Setting the first log weight to zero chooses a reference; it does not make the
probability of category zero vanish. Dividing by the sum makes the probabilities
add to one. Rating-scale MFRM shares the step offsets across items; partial-credit
MFRM allows item-specific steps. Ordered score labels do not require fitted
adjacent-category step offsets to be increasing. Their interpretation differs
from cumulative cutpoints in an ordered-logistic model.

## Work through a three-category example

Consider categories 0, 1 and 2, with illustrative step offsets
``d_{i1}=-0.5`` and ``d_{i2}=0.5``. Set ability to 0.8 and item difficulty to
0.3. For rater severity 0.5, the net location is ``x=0.8-0.3-0.5=0``.
The adjacent log odds are 0.5 and -0.5, so the category log weights are
``(0,0.5,0)``. Exponentiating and normalizing gives approximately
``(0.2741,0.4519,0.2741)``.

| Rater severity | Net location ``x`` | ``P(Y=0)`` | ``P(Y=1)`` | ``P(Y=2)`` |
| ---: | ---: | ---: | ---: | ---: |
| 1.5 | -1 | 0.5741 | 0.3482 | 0.0777 |
| 0.5 | 0 | 0.2741 | 0.4519 | 0.2741 |
| -0.5 | 1 | 0.0777 | 0.3482 | 0.5741 |

A more severe rater lowers the score distribution while the person and item
stay the same. These are conditional probabilities at chosen parameter values,
not estimates from data or a claim that this particular prior or design is suitable.

This small Julia calculation reproduces the table without a package or MCMC:

```@example rating_probabilities
using Printf

function category_probabilities(x, steps)
    logweights = vcat(0.0, cumsum(x .- steps))
    weights = exp.(logweights .- maximum(logweights))
    return weights ./ sum(weights)
end

steps = [-0.5, 0.5]
for severity in (1.5, 0.5, -0.5)
    x = 0.8 - 0.3 - severity
    probability = category_probabilities(x, steps)
    @assert isapprox(sum(probability), 1.0)
    @assert all(isapprox.(log.(probability[2:end] ./ probability[1:end-1]), x .- steps))
    @printf("severity=%4.1f  x=%4.1f  probabilities=(%.4f, %.4f, %.4f)\n",
        severity, x, probability...)
end
```

Subtracting the maximum log weight before exponentiating preserves the
probabilities and avoids unnecessarily large exponentials.

## What GMFRM and MGMFRM change

The implemented scalar GMFRM uses the adjacent log odds

```math
\log\frac{P(Y_{pir}=k)}{P(Y_{pir}=k-1)}
=a_i c_r(\theta_p-b_i-s_r-d_{rk}),
\qquad a_i>0,\ c_r>0.
```

Here ``a_i`` is item discrimination and ``c_r`` is rater consistency. Increasing
their product multiplies all category log weights, concentrating probability
on the most favored category or tied categories. It does not always move
probability toward the highest score. Severity shifts where the distribution
lies; consistency changes its concentration. Consistency is not a reliability
coefficient, agreement percentage, or accuracy against an external standard.
The steps ``d_{rk}`` belong to the rater in this scalar model.

The implemented MGMFRM instead uses

```math
\log\frac{P(Y_{pir}=k)}{P(Y_{pir}=k-1)}
=1.7\,c_r\left(\sum_{d=1}^{D}a_{id}\theta_{pd}-b_i-s_r-d_{ik}\right).
```

There are ``D`` named abilities for each person. A zero in Q fixes the corresponding
``a_{id}`` to zero; an active entry permits a positive loading. The steps now
belong to the item. The factor 1.7 is part of this implementation's source
equation; scalar GMFRM above and fixed-coefficient MFRM use unit scaling.
Item loadings in MGMFRM multiply abilities inside the sum, whereas scalar
GMFRM discrimination multiplies the whole bracket. Thus raw parameter values
cannot be compared across these families as though their units and priors were identical.

For fixed-coefficient multidimensional MFRM, the adjacent log odds are
``\sum_d Q_{id}\theta_{pd}-b_i-s_r-d_{ik}``: active coefficients are one and
there is no estimated consistency multiplier. This provides a distinct
multidimensional alternative without estimating active loadings.

In MGMFRM, multiple active abilities enter an **additive weighted sum**. If an
item uses reasoning and communication, a higher value in one can offset a lower
value in the other. An interpretation requiring a person to exceed a separate
minimum in *both* abilities would require a different response mechanism.
The [source discussion](model-equations.md#Generalized-Partial-Credit-and-Multidimensional-Structure)
explains why terminology in an article must be read alongside its actual equation.

## Compensatory and non-compensatory response rules

These words describe **how abilities combine in the response equation**. Imagine
an item assessing reasoning and communication. In a compensatory model, stronger
reasoning can offset weaker communication on that item, to an extent determined
by its loadings. In a non-compensatory model, a weakness in a required ability
limits performance even when another ability is strong. This need not be a
literal pass/fail cutoff; the exact restriction depends on the response rule.

For the implemented MGMFRM, the relevant sum is
``u_i=a_{i1}\theta_1+a_{i2}\theta_2``. With loadings ``(2,1)``, profiles
``(0,2)`` and ``(1,0)`` both give ``u_i=2``. Holding this item's remaining
parameters and the rater fixed gives exactly the same category probabilities.
This is a conditional tradeoff on one item. Other items with different loadings
can distinguish these people; their full posteriors need not be the same.

For contrast, a binary product rule could be
``P(Y=1)=\sigma(\theta_1)\sigma(\theta_2)``, where
``\sigma(z)=1/(1+e^{-z})``. Holding the second ability fixed bounds success
probability by ``\sigma(\theta_2)``, however large the first ability becomes.
This illustrates a conjunctive restriction, but is **not an ordinal model fitted
by this package**. No product, minimum or other operationally non-compensatory
alternative is currently implemented.

Uto (2021) uses the term *non-compensatory*, while the published equation and
Stan code aggregate abilities additively. We preserve the source terminology
separately from this algebraic interpretation. Do not infer a conjunctive
response mechanism from that label. The
[detailed source comparison](experimental.md#Dimension-aggregation-and-item-structure)
links the article, original Stan code and contrasting response equations.

## Within-item and between-item multidimensionality

These terms describe **which abilities enter each item**, rather than how those
abilities combine. Here, *within* and *between* refer to items, not within-person
versus between-person effects in a multilevel model.

| Item structure | Example Q rows for reasoning and communication | Reading |
| --- | --- | --- |
| Between-item | I1: `(1,0)`; I2: `(0,1)` | Each item measures one ability; different items address different abilities. |
| Within-item | I3: `(1,1)` | This item measures both abilities. |
| Mixed in the package contract | I1: `(1,0)`; I2: `(0,1)`; I3: `(1,1)` | Pure and cross-loaded items coexist. |

These rows illustrate the structure, not a sufficient calibration design. The
[ACER ConQuest manual](https://conquestmanual.acer.org/s2-00.html#within-item-and-between-item-multidimensionality)
uses *within-item* at test level when any item measures several dimensions. Our
contract additionally distinguishes a mixed collection of pure and cross-loaded
items. A small estimated positive loading is not the structural zero declared
by Q.

A within-item model can use either a compensatory or a non-compensatory rule.
In this package it uses the additive rule above. A between-item structure has
no cross-ability tradeoff **inside a single item**, because that item uses only
one ability; this does not make it a conjunctive model. Correlation between
abilities is another separate choice: between-item does not mean uncorrelated,
and within-item does not itself imply correlated population abilities.

The fixed-Q independent MGMFRM branch can represent cross-loaded items subject
to its warning-bearing design and identification checks. Its current correlated
2D fitting route is restricted to between-item structure. In the
[gallery](visualization-gallery.md#Compare-items-and-raters), each saved-fit item
loads on only one dimension: its probability surface is flat along the other
ability axis. A 3D display alone does not establish within-item measurement.

## Why origins, units and priors matter

In the simple MFRM equation, adding the same constant to every ability and item
difficulty leaves ``\theta_p-b_i`` unchanged. The ratings alone cannot choose
that common origin. Reference constraints and priors define the coordinates in
which estimates are reported. Zero is a reference on that scale, not absence
of ability or severity in an absolute sense.

Estimated loadings introduce further scale ambiguity: multiplying abilities
by a positive constant and dividing their loadings by that constant preserves
the weighted ability contribution. The MGMFRM ability prior fixes a population
origin and marginal scale, while other constraints handle rater and step
coordinates. That population convention does not force the observed persons'
sample mean to zero or variance to one.

A proper prior can give a finite posterior even where the likelihood alone
does not distinguish parameters. Finite intervals therefore do not prove that
the data identify every separate effect. Compare meaningful contrasts on a
declared scale, examine prior sensitivity, and consult
[Estimands, origins and units](@ref "Estimands, origins and units") for the
less obvious consequences of unequal loadings.

Prior SDs must also name their coordinate: an SD for a log loading is not an
SD for a positive loading. A supplied ability prior SD is not an estimated
population SD or a person's posterior standard error. The original generalized
free-coordinate prior and the explicit normalized-prior alternatives can imply
different distributions after constraints, including different treatment of
raters. See [Experimental Models](experimental.md) before selecting their scales.

## What Bayesian estimation computes

Let ``\phi`` collect the unknown abilities, facet parameters and any estimated
correlations. Bayesian inference combines a likelihood with a prior:

```math
p(\phi\mid y)\propto p(y\mid\phi)\,p(\phi).
```

The likelihood describes observed scores conditional on the parameters. The
prior describes their distribution before using these scores. The posterior
describes their uncertainty after combining those ingredients. MCMC provides
dependent numerical draws intended to approximate that posterior; increasing
the draw count improves computation only when the sampler is exploring it adequately.

The baseline likelihood multiplies rating probabilities conditional on the
modeled parameters. This assumes conditional independence, not independence
of the observed scores before accounting for shared persons, items and raters.
Unmodeled variation shared by ratings of the same response can violate that
assumption. Merely storing a response identifier does not repair the likelihood.

Posterior prediction averages over parameter uncertainty:

```math
P(Y^{\mathrm{new}}=k\mid y)
=\int P(Y^{\mathrm{new}}=k\mid\phi)\,p(\phi\mid y)\,d\phi.
```

In practice, average the category probabilities over joint posterior draws.
Plugging the posterior mean of each parameter into a nonlinear probability
formula generally gives a different result. Prediction for an unseen person
also needs that person's ability distribution; it is a different target from
another rating of a person already represented in the fitted data.

## How correlation and LKJ fit into the model

For several abilities, a population prior can use
``\boldsymbol\theta_p\sim N(0,SRS)``. The diagonal matrix ``S`` contains
marginal SDs, while ``R`` contains correlations. Correlation describes population
association between abilities, not agreement between raters or causation.

An LKJ prior has density ``p(R\mid\eta)\propto\det(R)^{\eta-1}`` on valid
correlation matrices. At ``\eta=1`` it is uniform over those matrices; for
``\eta>1`` it favors matrices near identity. This does not mean all pairwise
correlations are independently uniform. Its implications depend on dimension.
Computations often use a lower-triangular Cholesky factor ``L`` with ``R=LL^\top``.
Changing coordinates changes the density: the Cholesky density is generally
not constant at ``\eta=1``. See the [Stan correlation-distribution reference](https://mc-stan.org/docs/functions-reference/correlation_matrix_distributions.html).

These formulas extend mathematically beyond two dimensions. The package's
fitting interface currently admits only its specified two-dimensional correlated
models; a mathematical generalization does not establish a fitted or validated
higher-dimensional workflow. Identity population correlation likewise does not
make every posterior estimate or observed score independent.

Continue to [Reading Results and Comparing Models](interpreting-results.md)
to see which outputs answer which questions.
