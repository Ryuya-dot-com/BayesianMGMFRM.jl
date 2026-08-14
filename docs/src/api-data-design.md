# Data and Design API

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
mfrm_spec
getdesign
design_identity
constraint_table
identification_declarations
model_ladder
model_manifest
model_equation
model_family_contract
mgmfrm_validation_protocol
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
external_bridge_result_receipt
rating_design_check
testlet_design_check
```
