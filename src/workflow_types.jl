"""
    AbstractMFRMSpec

Common supertype for specifications returned by [`mfrm_spec`](@ref), including
Bayesian targets, prior-free frequentist specifications and legacy `FacetSpec`.
Use this type when annotating functions that accept different measurement models.
Inspect a specification with [`design_summary`](@ref) and [`validate_design`](@ref).

Concrete fields, priors, supported estimation methods and additional operations
remain model-specific. This type does not imply that every model accepts every
keyword to [`fit`](@ref).
"""
abstract type AbstractMFRMSpec end

"""
    AbstractMFRMFit

Common supertype for native fits of `mfrm_spec` specifications: additive MFRM,
shared-effect MRCML, GMFRM/MGMFRM, JMLE/MMLE and legacy fits. For example:

```julia
my_summary(fitted::AbstractMFRMFit) = design_summary(fitted)
```

Use the model's documented operations instead of assuming a common field layout.
A frequentist fit does not acquire MCMC draws or Bayesian posterior operations
through this supertype. Saved reports and portable handoff bundles are separate
objects, not native fits. `Legacy.MFRMFit` names the older concrete fit type;
use `AbstractMFRMFit` for functions intended to accept standard v0.2 fits.
"""
abstract type AbstractMFRMFit end
