# Model Equations

`BayesianMGMFRM.jl` keeps model-equation metadata separate from fitting
availability. The [`model_equation`](@ref) contract records the intended family,
category kernel, primary-source references, required parameter blocks,
identification restrictions, implementation gaps, and whether a specification is
fit-ready.

The current public fitting surface is the minimal MFRM/RSM/PCM slice plus
guarded experimental generalized candidates: the scalar rater-consistency
GMFRM path and the fixed-Q confirmatory MGMFRM path with `dimensions >= 2`.
Broader GMFRM/MGMFRM specifications expose source-aligned manifests and preview
compiler rows for review, while broad generalized fitting remains guarded or
under development as described in [Scope and Releases](scope.md).

## Source Map

- Partial-credit lineage: Masters (1982), DOI
  [`10.1007/BF02296272`](https://doi.org/10.1007/BF02296272).
- Rating-scale lineage: Andrich (1978), DOI
  [`10.1007/BF02293814`](https://doi.org/10.1007/BF02293814).
- Generalized MFRM target: Uto and Ueno (2020), DOI
  [`10.1007/s41237-020-00115-7`](https://doi.org/10.1007/s41237-020-00115-7).
- Multidimensional generalized MFRM target: Uto (2021), DOI
  [`10.1007/s41237-021-00144-w`](https://doi.org/10.1007/s41237-021-00144-w).

See [API](api.md) for the rendered [`model_equation`](@ref) docstring.

## Independent Known-Truth Ordinal Kernel

The LD1a simulation API deliberately does not call the fitted probability or
likelihood implementation. For row `i`, category `0` has log weight zero and
the standalone adjacent-category recurrence is

```math
\ell_{i0}=0, \qquad
\ell_{ik}=\ell_{i,k-1}+\eta_i-\delta_{ik}, \qquad
P(Y_i=k)=\frac{\exp(\ell_{ik})}{\sum_h \exp(\ell_{ih})}.
```

The generating location records every additive component separately:

```math
\eta_i = A_{p[i],j[i]}-\beta_{j[i]}-\rho_{r[i]}
       +u_{p[i],t[i]}+h_{r[i],s[i]}-g_{r[i],t[i]}
       -d_{r[i]}z_i,
\qquad
A_{pj}=\sqrt{1-(\lambda q_{j2})^2}\,\theta^{(1)}_{p}
       +\lambda q_{j2}\theta^{(2)}_{p}.
```

Here the optional terms represent person-by-testlet variation, rater-response
halo, rater-by-task severity, an omitted second dimension, and sequence drift.
The omitted-dimension control crosses active and inactive items within every
testlet and uses the square-root weight above so its active-item latent variance
does not increase merely because a second independent ability was added.
Individual LD1a scenarios activate only their declared components. The
zero/near-zero/small/moderate/large scales are study-local inputs, not model
defaults or universal practical thresholds. This independent data-generating
equation is generator evidence only; repeated LD1b calibration and every
fitted clustered-effect equation remain future gates.

Every generated row is sampled independently after conditioning on the full
recorded truth. This differs from the baseline MFRM assumption: omitting a
shared testlet, halo, or second-dimension component leaves shared latent
variation, whereas rater-by-task and sequence terms misspecify the baseline
mean structure. Generated bundles report these cases separately through
`baseline_mfrm_assumption_status` instead of an unqualified global-local-
independence boolean.
