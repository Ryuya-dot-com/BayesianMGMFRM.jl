# Compare two groups on a shared rating scale

How much higher or lower is the receiving group's mean ability at the same level of practice? In this synthetic example, 120 writers each answer four or five of the same five items. The two groups overlap at every practice level. There are 514 scores on a 0–3 scale. Item IDs link the groups. Writer IDs link each person's scores to their group and practice level.

## Declare the link and fit the model

The two CSV files ship with the package. The roster has one row per writer, including the group label and numeric practice covariate. The rating table has one row per observed score. These fixtures contain plain, comma-separated fields.

```julia
using BayesianMGMFRM
using BayesianMGMFRM.Distributions: Normal, LogNormal
input = joinpath(pkgdir(BayesianMGMFRM), "examples", "data")
rows(name) = split.(readlines(joinpath(input, name))[2:end], ',')
y = rows("linked-ratings.csv")
r = rows("linked-roster.csv")
ratings = (id=String.(first.(y)), item=String.(getindex.(y, 2)), score=parse.(Int, last.(y)))
roster = (id=String.(first.(r)), study=String.(getindex.(r, 2)), practice=parse.(Float64, last.(r)))

population = (roster=roster, person=:id, group=:study, reference="reference",
    covariates=(:practice,), intercept=false, coefficient_prior=Normal(0, 1.1),
    sd_prior=LogNormal(0, 0.5), person_coordinates=(information_cutoff=5.0,))
model = mfrm_spec(ratings; person=:id, score=:score, facets=(item=:item,),
    category_levels=0:3, steps=:global, population,
    fixed_calibration=(facets=(item=Dict("I1" => -0.8),),),
    prior_sd=(facets=(item=1.0,), step=0.75))
f = fit(model; method=:nuts, chains=4, warmup=400, ndraws=800, seed=2602, target_accept=0.93)
qualify(f)
```

| Component | Interpretation in this example |
| --- | --- |
| Location and unit | The reference-group mean at practice zero is fixed at zero. The ability coefficient for each adjacent-category logit is fixed at one. Both population SDs are estimated. |
| Item and step calibration | Item I1 is fixed at −0.8 logits in both groups. The other four locations and two independent contrasts for three shared, sum-zero steps are estimated jointly across groups. |
| Population | The model estimates the receiving-group mean at practice zero and one common practice slope. With parallel slopes the adjusted difference is the same at every shared practice value. |
| Computation | The optional information cutoff fixes each person's sampling coordinates before fitting. The example used centered coordinates for 51 writers and noncentered coordinates for 69. It does not set any writer's ability or determine the reporting scale. |

This saved example explicitly sets `intercept=false` to reproduce its original
reference-group mean constraint. New grouped fits estimate that mean by default,
including with hard fixed calibration. Fix it only when a zero reference mean is
part of the substantive calibration assumptions.

## Read the contrast and save the result

```julia
pv = plausible_values(f)
difference = contrast(pv; group="receiving", reference="reference")
@show difference.estimate difference.lower difference.upper difference.source_qualified
save_fit("linked-writers.jls", f)
```

In the reference run, the receiving-group mean was **0.477 logits higher** at equal practice (95% posterior interval 0.149 to 0.838). The group SDs were 0.654 for the reference group and 0.934 for the receiving group. Calling `contrast(f; group="receiving", reference="reference")` directly on the grouped Bayesian fit computes the same draw-paired group contrast. The contrast uses the group coefficient in each joint draw. Averaging individual plausible values would answer a different question about the sampled writers. The interval propagates uncertainty in the estimated measurement and population parameters, conditional on I1's specified value and the common item and step calibration. A panel-wide change in difficulty could mimic a group shift. Check the substantive basis for the common calibration before interpreting an applied contrast.

Start another Julia process in the same project environment and working directory. A native fit preserves joint states, IDs and sampler diagnostics.

```julia
using BayesianMGMFRM
saved = load_fit("linked-writers.jls")
difference = contrast(plausible_values(saved);
    group="receiving", reference="reference")
@show difference.n_draws difference.estimate difference.lower difference.upper difference.source_qualified
```

For the example the reopened contrast uses all 3,200 retained draws. For one-dimensional marginal maximum likelihood, use `fit(model; method=:mmle)` after omitting the NUTS-specific `person_coordinates` setting from the declaration. Its conditional plausible values hold the fitted calibration and population parameters fixed. See [frequentist fitting and transfer of calibration uncertainty](frequentist-mfrm.md). For an existing TAM calibration or custom category scores, see [constructing and inspecting the category design](design-matrix-mrcml.md).

## [Four calibration and equating modes](@id four-equating-modes)

Choose a calibration mode according to whether external anchor uncertainty must be propagated into receiving-cohort contrasts:

| Mode | Declaration in `mfrm_spec` / R `fit_mgmfrm` | Uncertainty and empirical coverage boundary |
| :--- | :--- | :--- |
| **Hard facet anchors (`:hard`)** | `fixed_calibration = (facets = (item = Dict("I1" => -0.8),),)` (or R `fixed_calibration = list(facets = list(item = c(I1 = -0.8)))`) | Holds anchored facet locations exact with zero external variance (`uncertainty = :conditional_on_fixed_calibration`). When source calibrations carry finite-sample estimation error, plug-in fixed anchoring omits linking variance: in two-form linking simulations under moderate source calibration error, nominal 95% group-contrast intervals drop to **`72%–75%`** empirical coverage. |
| **Fixed step calibration (`:step`)** | `fixed_calibration = (steps = Dict(:global => Dict(1 => -0.6, 2 => 0.6)),)` | Holds adjacent-category step thresholds fixed across administrations, conditional on unchanged rubric category functioning. |
| **Subset mean / sum constraints (`:group_mean`)** | `fixed_calibration = (groups = [(block = :rater, levels = ["R1", "R2"], mean = 0.0)],)` (or R `fixed_calibration = list(groups = list(...))`) | Applies unweighted equal-level subset equations (`subset_weighting_convention = "unweighted_equal_levels"`), resolving panel-nested aliasing only under the explicit substantive assumption that the constrained subsets share the declared mean or sum. Keep `fixed_calibration` distinct from person-population `population` / R `group`. |
| **Covariance-propagating soft calibration (`:soft`)** | `calibration = external_transfer` (multivariate normal mean vector and joint covariance matrix on Bayesian NUTS) | Propagates full off-diagonal source calibration covariance into the receiving posterior, restoring nominal 95% group-contrast coverage to **`93.5%–95.8%`** when common-item invariance holds. |

## [Non-identifiability boundaries: group impact, DFF, drift, and rating mode](@id equating-identification-boundaries)

No statistical linking mode can separate two effects that enter every linked observation identically:

- **Group ability impact vs. uniform panel-wide DFF:** If every rater in a panel grades one examinee group uniformly more severely by $\Delta\bar{\rho}$ logits while that group's latent mean ability differs by $\Delta\mu_g$, the likelihood depends only on $\Delta\mu_g - \Delta\bar{\rho}$. Likewise, combining person-group regression (`population` / `predictors`) with `interactions` requires an invariant reference link; doubly centered rater-by-item `interactions` capture relative differential facet functioning around main effects, not a uniform panel-wide severity offset.
- **Uniform anchor drift and rating-mode offset ($\delta_{\text{vid}}$):** A common severity shift across all anchor raters/tasks between cohorts—or a systematic mode offset $\delta_{\text{vid}}$ when 2D video-recorded ratings are linked to live ratings without cross-mode linked performances—shifts the estimated receiving-group mean one-for-one. Temporal severity drift (`Experimental.RaterDrift` `RW1`) and local-dependence extensions (`person-testlet`, `StarAssociation`, `CriterionCollapse`) have model-specific assumptions and available operations; see [Scope and Releases](scope.md#dff-priors-and-non-goals).
