# Data and Design API

!!! note "Unreleased documentation preview — 13 October 2026"
    This manual includes unreleased interfaces and examples. It is not the
    documentation of an installed release. Model support and scientific
    acceptance remain as stated on each page.

Enter `spec` at the Julia prompt to read a `FacetSpec`'s slopes, category-step
owner, fitting entry and warning counts. In a script, use
`show(stdout, MIME"text/plain"(), spec)`. `println(spec)` retains the compact
one-line representation. See [option meanings](learning-guide.md#Check-what-this-package-can-currently-fit)
for the compatibility discrimination selectors and validation-only `bias` terms.

Functions that expose both detailed compatibility records and concise
reader-facing records use a `view` keyword. Existing calls retain
`view = :full`. For reports or shared structured output, use `view = :public`:

```julia
layout = fit_ready_parameter_layout(spec; preview = true, view = :public)
domain_rows = domain_compilation_summary(spec; preview = true, view = :public)
ladder = model_ladder(view = :public)
rating_check = rating_design_check(spec; view = :public)
software = related_software_capability_matrix(view = :public)
```

The public parameter-layout and domain rows report `stability`,
`fit_available`, `entrypoint`, and `claim_scope` directly. They preserve raw
and constrained parameter names, blocks, transforms, constraints, priors, and
fixed-Q information. Stable MFRM/RSM/PCM fitting uses `fit(spec)`; the limited
scalar-GMFRM and fixed-Q confirmatory MGMFRM subsets use
`BayesianMGMFRM.Experimental.fit(spec)`. A preview layout by itself is not a
claim that every represented generalized configuration can be fitted.

```@docs
BayesianMGMFRM
FacetData
ValidationIssue
ValidationReport
FacetSpec
FacetDesign
validate_design
validation_suggestions
ordinal_response_pattern_audit
mfrm_spec
getdesign
design_identity
constraint_table
identification_declarations
model_ladder
model_manifest
model_equation
model_family_contract
model_surface_check
q_matrix_validation
fit_ready_parameter_layout
domain_compilation_summary
design_row_table
linear_predictor_table
linear_predictor_values
initial_params
loglikelihood
logposterior
logprior
threshold_map_data
facet_response_table
coverage_summary
coverage_matrix
rater_overlap
anchor_linking_summary
anchor_refit_plan
facets_bridge_bundle
conquest_bridge_bundle
save_external_bridge_bundle
validate_external_bridge_bundle
load_conquest_parameter_export
load_conquest_semantic_parameters
BayesianMGMFRM.load_conquest_reference_parameters
external_bridge_result_receipt
rating_design_check
testlet_design_check
design_summary
with_options
prior_draw
simulate
```

## Glass-Box Researcher Transparency Surface

These functions expose exact mathematical contracts, parameter charts, facet
bases, coordinate bijections, triangular change-of-variables Jacobians,
analytical or forward-mode gradients, CmdStan data dictionaries, and sampler
settings across package targets.

```@docs
contract
parameter_names
facet_basis
coordinates
to_ncp_reference
from_ncp_reference
reparameterize_point
reparameterize_draws
log_jacobian_to_ncp
logdensity_and_gradient
stan_data
sampler_controls
```

## Compatibility diagnostic names

`rating_design_audit`, `model_surface_audit`, and `testlet_design_audit` are
retained at package root for source compatibility in the `0.1.x` line. New
reader-facing workflows should use `rating_design_check`,
`model_surface_check`, and `testlet_design_check`. Retention does not make the
detailed audit payloads a new stable extension surface.

```@docs
rating_design_audit
model_surface_audit
testlet_design_audit
```
