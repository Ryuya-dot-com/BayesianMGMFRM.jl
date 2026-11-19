# Person-by-Testlet Dependence via Shared Cluster Residuals

When several items or rated tasks share a common stimulus, passage, prompt bundle,
or clinical case, responses from the same person within that bundle can share a
local deviation beyond overall person ability and item or rater severity. In the
scalar unit-slope Rasch and partial-credit testlet literature (Bradlow, Wainer,
and Wang, 1999; Wang and Wilson, 2005; Eckes and Baghaei, 2015), rating row $n$
for person $p(n)$, item $i(n)$ in testlet $d(n)$, and rater $r(n)$ has adjacent-category
log-odds

$$\log \frac{P(Y_n = k \mid \cdot)}{P(Y_n = k - 1 \mid \cdot)} = \theta_{p(n)} + \mu + u_{p(n), d(n)} - \beta_{\text{item}, i(n)} - \beta_{\text{rater}, r(n)} - \tau_{g(n), k - 1},$$

with independent cluster deviations $u_{p, d} \sim \mathcal{N}(0, \sigma_u^2)$ across
person-by-testlet clusters $c = (p, d)$.

## Reuse of the explanatory population and performance workflow

No separate testlet fitter is needed for this scalar unit-slope target. Create an
explicit `person_testlet` column identifying each observed `(person, testlet)`
cluster, declare `performance = :person_testlet`, and place `person_testlet` in
`facets` and `population`:

```julia
using BayesianMGMFRM
using Distributions: Normal, LogNormal

spec_testlet = mfrm_spec(ratings;
    person = :person,
    performance = :person_testlet,
    score = :score,
    facets = (person_testlet = :person_testlet, item = :item, rater = :rater),
    steps = :global,
    category_levels = 0:3,
    population = (
        person = LogNormal(log(0.8), 0.35),
        person_testlet = LogNormal(log(0.45), 0.40),
    ),
    prior_sd = (facets = (item = 0.7, rater = 0.5), step = 0.5),
    intercept = Normal(0.0, 0.8),
)
validate_design(spec_testlet)
```

### Sign convention and exact target equivalence

- Named facet coordinates represent **severity** (`positive lowers ratings`), so
  the stored model coordinate `person_testlet[c]` equals $-u_{p, d}$, while
  `residual_sd[person_testlet]` equals $\sigma_u > 0$ in unit adjacent logits.
- Because the standard-normal raw coordinate density is symmetric around zero with
  unit reflection Jacobian, the normalized joint posterior density, scientific
  prior factors, coordinate volume, and Gauss–Hermite cluster marginal likelihood
  coincide with the positive-sign testlet parameterization.
- Setting `population = (person = LogNormal(log(0.8), 0.35), person_testlet = 0.0)`
  constructs the **exact matched no-testlet comparator** ($u_{p, d} \equiv 0$)
  with zero unconstrained cluster parameters, identical Helmert finite-facet and
  threshold priors, and the same held-cluster observation binding.

## Separating testlet difficulty, item difficulty, and local dependence

Check what the design actually identifies before fitting:

1. **Nested versus crossed items and testlets.** When each item belongs to a
   single testlet, finite sum-zero `item` difficulties already span mean
   differences among testlets; adding a second unconstrained finite `testlet`
   facet aliases the mean design and is rejected by `validate_design`. Declare a
   separate `testlet` facet only when items are crossed with testlets or when
   testlet difficulties are explicitly pooled in `population`.
2. **Multiple testlets per person.** If each person appears in only one testlet,
   `person` and `person_testlet` groupings coincide and `validate_design`
   rejects the aliased variance components.
3. **Replication within `(person, testlet)` clusters.** Estimating
   `residual_sd[person_testlet]` requires repeated observations within clusters
   (multiple items in the testlet and/or multiple raters). Even when structural
   checks pass, sparse within-cluster replication leaves $\sigma_u$ sensitive to
   its `LogNormal` prior; inspect `prior_sensitivity` alongside `fit_report`.
4. **Residual screening versus joint fitting.** Use `testlet_design_audit` and
   `local_dependence_audit` to audit design support and residual dependence on
   fitted baseline models; use the specification above when estimating $\sigma_u$
   jointly.

## Held-cluster comparison and prediction targets

Ratings inside the same `(person, testlet)` cluster share $u_{p, d}$, so
row-wise WAIC or rating-wise LOO does not measure generalization to an unseen
cluster. Score whole `(person, testlet)` profiles by integrating
`person_testlet` jointly:

```julia
c_testlet = criteria(fit_testlet; unit = :performance, integrate = :person_testlet)
c_null = criteria(fit_null; unit = :performance, integrate = :person_testlet)
cmp = compare_models("Person × testlet" => c_testlet, "Matched no-testlet" => c_null;
    criterion = :psis_loo, independent_model_rng = true)
```

For forward prediction, match `mode` and `new_owners` to the intended target:

- **Known `(person, testlet)` cluster** (for example, another known rater scoring
  an observed cluster): `predict(fit_testlet; data = rows_known, mode = :known_owners)`.
- **Known person encountering a new testlet cluster** (integrating fresh
  $u_{p, d_{\text{new}}} \sim \mathcal{N}(0, \sigma_u^2)$ draws on the logit
  scale without zero-effect substitution):
  `predict(fit_testlet; data = rows_new_cluster, mode = :new_owners, new_owners = (:person_testlet,), seed = 401)`.
- **New person and new testlet cluster**:
  `predict(fit_testlet; data = rows_new_person, mode = :new_owners, new_owners = (:person, :person_testlet), seed = 402)`.

Finite sum-zero facets (such as fixed `item` panels) must remain known; unseen
items require declaring `item` in `population`. Multidimensional testlet loadings,
rater-specific halo mechanisms, and combined testlet-halo-DFF models remain
outside this scalar route.
