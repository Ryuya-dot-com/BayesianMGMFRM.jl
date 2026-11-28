# Read a rating as category-design rows

Consider one writer receiving category 2 on task T1, criterion Content, from rater R2. Suppose the allowed scores are 0, 1 and 2. The likelihood selects the row for category 2 in its numerator and includes **all three** rows for this task–criterion–rater combination in its denominator. Another writer rated on the same combination can reuse those rows. The writer ID selects the ability.

Let the difficulty of this combination be the sum of task difficulty, criterion difficulty and rater severity. The table shows coefficients of these *physical* parameters. The two steps belong to Content and sum to zero within Content. Write its first step as δ and its second as −δ. Positive difficulty or severity lowers the adjacent-category logit.

| Score | Task T1 | Criterion Content | Rater R2 | Content step contrast δ | Ability score B |
| ---: | ---: | ---: | ---: | ---: | ---: |
| 0 | 0 | 0 | 0 | 0 | 0 |
| 1 | −1 | −1 | −1 | −1 | 1 |
| 2 | −2 | −2 | −2 | 0 | 2 |

The row for score 2 accumulates both steps, so its coefficient on δ is zero. Subtracting row 1 from row 2 gives the second adjacent logit: ability minus the three locations **plus** δ. With global steps, all criteria share one centered step vector. With criterion-owned steps, each criterion has its own centered vector. The compiled free columns of A use the model's contrast basis. A fixed location contributes through the category offset. Inspect the transformation back to physical parameters when comparing software.

An LLTM can express task difficulty as a weighted sum of task features. For example, if T1 requires two source integrations, then a difficulty increment per integration enters its category rows with coefficients 0, −2 and −4. A task-specific residual requires an explicit residual model. A feature counts a task demand. The ability weight for a one-category increase is the adjacent difference in B. In a compensatory multidimensional PCM with fixed item row q, the category scoring vector is k times q. The scalar MRCML interface accepts one ability scoring column. See [fixed-Q correlated traits](correlated-3d.md) for a multiple-ability model.

## Inspect the structured design or supply arrays

Given `model` from [the linked group example](equating-and-populations.md), identify the rows for the first observed rating and their fixed offsets:

```julia
M = BayesianMGMFRM.MRCML
d = M.design_matrices(model)
u = d.pattern_of_row[1]
categories = d.pattern_ranges[u]
@show d.model_names d.A_model[categories, :] d.B_pattern[categories] d.offset_pattern[categories]
tam = M.to_tam(model)
@show size(tam.A) size(tam.B) tam.offset[u, :] tam.pid[1]
```

The TAM layout indexes generalized item, category and coefficient. Julia's category-array index 1 represents score 0 here. The exported response layout preserves repeated ratings with one person ID per row. Transfer the category offsets along with A and B when calibration is fixed. These arrays encode the measurement logits. To reproduce the grouped posterior, also match the population declaration, location constraints and joint priors.

For a minimal explicit TAM-style input, the following two items use one free difficulty for I2, a known zero difficulty for I1, and unit adjacent ability scores. The category steps are fixed at zero here.

```julia
using BayesianMGMFRM
A = zeros(2, 3, 1)
A[2, :, 1] .= [0, -1, -2]
B = zeros(2, 3, 1)
for i in 1:2
    B[i, :, 1] .= 0:2
end
resp = [0 1; 2 0; 1 2]
explicit = BayesianMGMFRM.MRCML.from_tam(A, resp; B, pid=["a", "b", "c"],
    item_names=["I1", "I2"], parameter_names=["difficulty_I2"])
validate_design(explicit)
```

For expanded multifacet TAM designs, supply the matching facet-cell order and repeated person IDs. For constrained coefficients, compare the exact category logits and the prior in free coordinates. Equal likelihoods alone leave room for different Bayesian intervals.

## Generalized Q-matrix and location-rank inspection

Scale-identified `GMFRM` and `MGMFRM` specifications built with `mfrm_spec` share the same generalized-item design-matrix inspection surface (`BayesianMGMFRM.MRCML.design_matrices`, `BayesianMGMFRM.GlassBox.facet_basis`, and `BayesianMGMFRM.GlassBox.constraint_table`), and accept label-keyed `q_matrix` inputs so item row order cannot silently drift from observed data:

```julia
q_named = [
    "Content_1" => [1, 0],
    "Content_2" => [1, 0],
    "Language_1" => [0, 1],
    "Language_2" => [0, 1],
    "Synthesis"  => [1, 1],
]
spec_mg = mfrm_spec(ratings_2d;
    person = :person, score = :score,
    facets = (item = :item, rater = :rater),
    steps = :item, category_levels = 0:3,
    q_matrix = q_named,
    dimension_labels = ["Comprehension", "Writing"],
    rater_slope_scope = :ability_only,
    aggregation = :softmin,
    prior = :default,
)

dm = BayesianMGMFRM.MRCML.design_matrices(spec_mg)
@show dm.location_step_rank.full_rank dm.intercept_slope_invariant size(dm.Q)
```

In `dm`, `A_model` maps `[ability_mean; item; rater; step]` onto category logits across unique `(item, rater, step_group)` patterns, `J_model` embeds the orthonormal Helmert zero-sum subspaces, `A_pattern = A_model * J_model` is audited by sparse QR (`dm.location_step_rank`) inside `validate_design(spec_mg)`, and `B_dimension_pattern` holds the reference dimension scoring weights. Disconnected specialist rater panels nested strictly within separate pure-item dimensions without cross-panel rater links or cross-loaded items are rejected upfront by `mfrm_spec`, while `validate_design(spec_mg)` additionally checks score-conditioned connectedness and Q-matrix pure-item anchoring before sampling. `dm.intercept_slope_invariant` indicates whether item, rater, and step locations remain linear (`true` when both `item_slope_scope` and `rater_slope_scope` equal `:ability_only`) or are scaled multiplicatively by rater consistency.
