# Experimental Generalized Models

`BayesianMGMFRM.Experimental` contains generalized models that are executable
only in the limited configurations documented below. They are not part of the
stable MFRM fitting contract, and their availability does not imply broader
GMFRM or MGMFRM support.

## Boundary

The namespace currently admits only two surfaces:

- one-dimensional source-aligned scalar GMFRM with positive item/task
  discrimination multiplied by positive rater consistency and rater-specific
  partial-credit steps;
- fixed-Q confirmatory MGMFRM with at least two dimensions, partial-credit
  steps, and fixed identity latent correlation.

Both reject anchors and fitted DFF terms. Broader discrimination, rating-scale
generalized kernels, exploratory or rotated loadings, and free latent
correlations remain outside the fitting boundary.

The compatibility selector `discrimination = :none` on MGMFRM means that no
broader generic discrimination family is selected. The experimental kernel still
estimates positive item-by-dimension discriminations at the active cells of
the fixed Q-matrix.

Likewise, the GMFRM compatibility selector `discrimination = :rater` does not
mean that item/task discrimination is absent. Its source-aligned kernel uses
the effective multiplier `item_discrimination[i] * rater_consistency[r]`.
Each rater has one step vector that is shared across items and persons on the
direct parameter scale. With `K` categories, the first step is fixed to zero,
`K - 2` steps per rater are free, and the final step is reconstructed so the
remaining steps sum to zero. The effective response-scale spacing also depends
on the item-by-rater discrimination product.

Inspect the executable contract before building an experimental workflow:

```julia
using BayesianMGMFRM

contract = BayesianMGMFRM.Experimental.surface_contract()
contract.families.mgmfrm
contract.families.gmfrm
contract.candidate_surfaces.mgmfrm_free_latent_correlation_2d
```

## Workflow

Specifications continue to use the common domain-language constructor. Design
preview, fitting, and cached fitting then cross the explicit namespace boundary:

```julia
spec = mfrm_spec(data;
    family = :mgmfrm,
    dimensions = 2,
    thresholds = :partial_credit,
    discrimination = :none,
    q_matrix = Bool[1 0; 0 1],
)

design = BayesianMGMFRM.Experimental.preview(spec)

fit_result = BayesianMGMFRM.Experimental.fit(spec;
    backend = :advancedhmc,
    ndraws = 500,
    warmup = 500,
    chains = 4,
    seed = 20260722,
)
```

If sampler counts are omitted, both guarded families currently use 100 warm-up
iterations and retain 100 draws per chain across two chains. Thus warm-up is
50% of the 200 iterations per chain and is discarded before the returned draw
matrix is constructed. This is a computational default, not analysis guidance.
The explicit 500 warm-up plus 500 retained draws in the example is also only an
example; choose and report a larger budget when diagnostics or the inferential
target require it. The stable MFRM `fit` entry point has a separate default of
1,000 warm-up plus 1,000 retained draws per chain.

Both guarded configurations accept either `backend = :advancedhmc` or
`backend = :cmdstan`. Each CmdStan route uses a package-owned Stan model,
samples the same raw-coordinate prior, applies the Julia identification
transform, and checks Stan's generated pointwise log likelihood against Julia
at every retained draw. The MGMFRM route remains fixed-Q and
identity-correlation only. Experimental `cached_fit` remains AdvancedHMC-only.
CmdStan is an optional external runtime; inspect it with
`cmdstan_backend_check()` before requesting that backend.

The older `fit(spec; experimental = true)` form remains available during the
migration, but new code should not depend on it. Passing `experimental` inside
the namespace is rejected because the namespace itself is the opt-in.

## Two-dimensional correlation density

The experimental namespace also provides a density for an exactly
two-dimensional simple-structure Q design with at least two
pure items per dimension and observations on both dimensions for every person.
It appends one raw coordinate `zρ` to the existing parameter vector and sets
`ρ = tanh(zρ)`. Person abilities receive a bivariate normal prior with fixed
marginal scale and correlation `ρ`; `ρ` receives a normalized two-dimensional
LKJ prior including the `tanh` Jacobian. Existing response likelihood terms and
all earlier raw coordinates remain unchanged.

```julia
correlation_spec = mfrm_spec(data;
    family = :mgmfrm,
    dimensions = 2,
    thresholds = :partial_credit,
    discrimination = :none,
    q_matrix = Bool[1 0; 0 1; 1 0; 0 1],
)

candidate = BayesianMGMFRM.Experimental.
    free_latent_correlation_2d_candidate(correlation_spec; lkj_eta = 2)

raw = BayesianMGMFRM.initial_params(candidate; zrho = 0.0)
state = BayesianMGMFRM.Experimental.
    free_latent_correlation_2d_state(candidate, raw)
diagnostics = BayesianMGMFRM.Experimental.
    free_latent_correlation_2d_diagnostics(
        correlation_spec,
        raw;
        finite_difference_coords = (1, 2, length(raw)),
    )
```

This exactly two-dimensional implementation accepts positive integer `lkj_eta` values.
Its name deliberately retains `2d`: independently transforming pairwise
correlations would not ensure a positive-definite matrix in higher dimensions,
where an LKJ-Cholesky parameterization is required. The candidate has no public
MCMC fit entry point, fit type, or cache key. Its public diagnostics evaluate
the density and selected gradient coordinates only; they do not assess sampler
convergence or response-level recovery.

## Stability and evidence limits

Experimental types, arguments, parameterizations, and report details may
change in a minor release. A successful run demonstrates only that exact
configuration. It does not establish broader source-equation coverage,
identification robustness, known-truth recovery, predictive validity,
sensitivity robustness, external-software agreement, construct validity, or
real-data validation.

Targeted Float64 tests exercise the stable-residual switch and extreme
subnormal inputs, but they do not establish numerical stability for every
dataset or sampler trajectory. At the smallest representable scales, gradient
contributions may round to zero; users should treat this as a documented
numerical limit rather than validation evidence.

Artifact digests support transport and reproducibility checks, but a matching
digest does not by itself establish scientific equivalence, execution
authenticity, or external validation.

```@docs
BayesianMGMFRM.Experimental
BayesianMGMFRM.Experimental.GMFRMFit
BayesianMGMFRM.Experimental.MGMFRMFit
BayesianMGMFRM.Experimental.surface_contract
BayesianMGMFRM.Experimental.free_latent_correlation_2d_contract
BayesianMGMFRM.Experimental.preview
BayesianMGMFRM.Experimental.free_latent_correlation_2d_candidate
BayesianMGMFRM.Experimental.free_latent_correlation_2d_state
BayesianMGMFRM.Experimental.free_latent_correlation_2d_diagnostics
BayesianMGMFRM.Experimental.fit
BayesianMGMFRM.Experimental.fit_cache_key
BayesianMGMFRM.Experimental.cached_fit
```
