# Facet workflow sources

`../facet_workflow.jl` includes these files in dependency order inside the
existing `BayesianMGMFRM` module. No additional module or public namespace is
introduced. Type identities, dispatch and record formats remain unchanged.

| Responsibility | Files |
| --- | --- |
| Tables, identifiers, validation | `data.jl`, `validation.jl` |
| Coverage, linking, design audit | `coverage_and_linking.jl`, `design_audit.jl` |
| Model support and release/provenance reports | `model_support.jl`, `software_comparison.jl`, `release_and_provenance.jl` |
| Q, anchors, specification, predictor layout | `q_matrix.jl`, `anchors_and_support.jl`, `model_specification.jl`, `design_and_predictors.jl` |
| Generalized-model coordinates and likelihoods | `gmfrm_coordinates.jl`, `mgmfrm_coordinates.jl`, `likelihood.jl` |
| Parameter/domain/model reports | `parameter_layout.jl`, `domain_and_surfaces.jl`, `raw_parameter_contracts.jl`, `gmfrm_api_contract.jl`, `mgmfrm_api_contract.jl`, `model_manifests.jl` |

This split preserves the existing reference-coded and inspection surfaces.
Standard isometric MRCML estimation still lives in the additive/MRCML sources.
Moving code here does not change model support or make research helpers lazy.
