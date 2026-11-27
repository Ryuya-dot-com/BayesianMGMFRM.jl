# Reading the implementation

Start with a concrete analysis in [`first_analysis_v02.jl`](../examples/first_analysis_v02.jl).
The route below follows its one-dimensional ordinal MFRM with
`prior = :default`. Public verbs dispatch on specification and fit types;
the file named `unified_workflow.jl` does not contain every model's methods.
Underscore-prefixed names below locate implementation details. Use the exported
workflow verbs in analysis code; underscored names can change between versions.

## Follow one analysis

| Question | Source and entry point | What to follow |
| --- | --- | --- |
| What is the public interface? | [`BayesianMGMFRM.jl`](BayesianMGMFRM.jl), [`workflow_types.jl`](workflow_types.jl) | Root exports, include order, `AbstractMFRMSpec` and `AbstractMFRMFit`. Concrete types retain their model-specific capabilities. |
| How does the rating table become a model? | [`additive_facets.jl`](additive_facets.jl), `mfrm_spec` | Explicit prior/model choices and dispatch to the MRCML constructor. This file opens the `AdditiveFacets` module, includes its implementations, then defines the public methods outside it. |
| How is the structured MRCML specification assembled? | [`mrcml_specification.jl`](mrcml_specification.jl), `compile_structured_mrcml` | Ordered stages for declarations, coordinate blocks, priors, response patterns and final specification. See the construction notes below. |
| Where are the constraints, priors and likelihood? | [`mrcml_design.jl`](mrcml_design.jl), `MRCMLTarget`, `_mrcml_unpack`, `logprior`, `coordinates`, `L.logdensity_and_gradient` | Mapping between unconstrained coordinates, person/facet/step effects and the ordinal likelihood. The `Float64` gradient uses reusable scratch buffers; a separate generic method supports other real-number types. |
| What happens when `fit` is called? | [`additive_facets.jl`](additive_facets.jl), `fit(::AdditiveFacets.MRCMLTarget)` → [`additive_facets_workflow.jl`](additive_facets_workflow.jl), `fit` | Estimator selection, validated target reconstruction, sampler coordinates, NUTS, conversion back to stored coordinates, and checked fit construction. |
| Where does NUTS execute? | [`mfrm_core/hmc_sampling.jl`](mfrm_core/hmc_sampling.jl), `_run_generalized_candidate_advancedhmc` | Chain execution, warmup, retained draws and sampler telemetry. The workflow calls this shared engine with an analytic gradient. |
| How are draws turned into results? | [`additive_facets_workflow.jl`](additive_facets_workflow.jl), `selected`, `diagnostics`, `qualify`, `summary`, `mcse`, `contrast` | Parameter selection, numerical warnings and joint-draw contrasts. For MRCML, `model_draws` dispatches to the overload in [`mrcml_design.jl`](mrcml_design.jl). |
| Where do fit statistics and prediction live? | [`additive_facets.jl`](additive_facets.jl), `diagnostics(::AdditiveFacets.Fit)`; [`mrcml_design.jl`](mrcml_design.jl), `_mrcml_fit_statistics`, `mrcml_predict`; [`mrcml_practitioner_reports.jl`](mrcml_practitioner_reports.jl) | Follow the requested diagnostic kind and conditioning. MCMC diagnostics, observed-response fit and predictive uncertainty answer different questions. |
| What is saved and checked on reopening? | [`additive_facets_workflow.jl`](additive_facets_workflow.jl), `checked`, `report`, `save_result`, `load_result`, `save_computed`; [`unified_workflow.jl`](unified_workflow.jl), `load_fit`, `save_report`, `load_report` | Native record/target checksums, run validation and computed JSON reports. The `PortableHandoff` module in [`stan_adapter.jl`](stan_adapter.jl) implements the portable handoff bundle used by the example. |

Julia can identify the actual dispatch for an object without running the method:

```julia
using InteractiveUtils
@which fit(spec)
@which posterior_summary(fitted)
@which BayesianMGMFRM.AdditiveFacets.model_draws(
    BayesianMGMFRM.AdditiveFacets.checked(fitted), fitted.record.run.draws)
```

Here `spec` is a specification and `fitted` is its fit result. Numerical qualification depends on
the actual diagnostics, including when an example runs successfully.

## Follow model construction

`mfrm_spec` in `additive_facets.jl` chooses the model family and explicit prior
convention. Grouped population models pass through `_compile_grouped_mrcml_spec`,
which matches the person roster to observation rows before adding group effects.
The ordinal structured route then calls `compile_structured_mrcml`:

| Stage | Implementation | Invariant to inspect |
| --- | --- | --- |
| Validate declarations and encode labels | [`inputs.jl`](mrcml_specification/inputs.jl), `_prepare_structured_mrcml` | Role columns, declared category support, threshold owners, prior choices and calibration restrictions are checked in order. A roster level is not inferred from its row position. |
| Construct facet, step and interaction coordinates | [`blocks.jl`](mrcml_specification/blocks.jl) | The named `layout` collects the affine map `xi_model = xi0_model + J_model * eta`, parameter names, block ranges and pending priors. Facets precede steps, then interactions. |
| Complete the prior layout | [`finalize.jl`](mrcml_specification/finalize.jl), `_complete_mrcml_prior_layout!` | Population location and transferred calibration follow the structural blocks; scale hyperparameters follow the other raw coordinates. |
| Build the response operator | [`finalize.jl`](mrcml_specification/finalize.jl), `_build_mrcml_response_operator` | Category log-weights accumulate person, facet, step and interaction contributions before identical response patterns are compressed. |
| Construct the target or prior-free specification | [`finalize.jl`](mrcml_specification/finalize.jl), `_finish_structured_mrcml` | Rank/identification results, prior symmetry, grouping and calibration receipts accompany the final object and its saved specification. |

The working `layout` and calibration receipts belong to one constructor call;
they are not new saved types. Helpers ending in `!` append to these working
arrays. The returned layout carries updated scalar cursors: raw sampler
coordinates, free structural coordinates (`eta`) and reconstructed model
coordinates can have different dimensions. Neither an anchored level nor a
deterministic LLTM reconstruction should consume a free coordinate merely
because it appears among the model-scale labels.

## Keep the three coordinate spaces distinct

1. **Sampler coordinates** are the unconstrained vector explored by HMC. With
   `mean_orthogonalization = :auto`, an eligible MRCML target uses a Givens
   rotation of person-mean and population-mean coordinates. The transformation
   and its gradient are in `_MRCMLMeanGivensTarget` and `_givens_to_raw` in
   `additive_facets_workflow.jl`.
2. **Stored raw coordinates** are the model's canonical unconstrained vector.
   `fit` maps the sampled initial state and every retained draw back before
   constructing its record. `producer.sampling_chart` records which sampler
   chart was used. Chain IDs and iteration order accompany these draws.
3. **Model coordinates** express person, facet and step effects used for
   summaries and contrasts. `model_draws` reconstructs them row by row. A
   contrast uses paired entries from the same posterior draw, preserving their
   dependence.

The Givens transformation preserves volume and the posterior target; it does
not change the model's identification constraints. Keep raw/model summaries,
sampler energy diagnostics and whole-fit qualification distinct. Numerical
qualification is not evidence of scientific validity or calibrated intervals.

## Locate other model routes and their tests

| Route | Implementation |
| --- | --- |
| One-dimensional JMLE/MMLE | [`frequentist_mfrm.jl`](frequentist_mfrm.jl), [`mrcml_frequentist.jl`](mrcml_frequentist.jl), [`frequentist_mfrm_api.jl`](frequentist_mfrm_api.jl). The MRCML `fit` dispatcher requires an explicit frequentist method and a compatible specification. |
| Scale-identified GMFRM/MGMFRM | [`mgmfrm_scale_identified_api.jl`](mgmfrm_scale_identified_api.jl) dispatches to [`mgmfrm_scale_identified.jl`](mgmfrm_scale_identified.jl). Follow its concrete target/fit methods rather than assuming MRCML's lifecycle implementation applies. |
| Legacy facet specifications and design inspection | [`facet_workflow/README.md`](facet_workflow/README.md), [`legacy_module.jl`](legacy_module.jl). The standard MRCML constructor is in the route above. |
| Research validation entry points | [`validation_suite.jl`](validation_suite.jl). Its namespace collects research operations; it does not imply that their source is loaded lazily. |

[`test/README.md`](../test/README.md) explains the test groups and shared
fixtures. For this route, start with `test/public_workflow_types.jl` (public
dispatch and persistence), `test/standard_onboarding.jl` (saved-fit reporting),
`test/additive_facets_workflow.jl` (generic additive operations),
[`test/mrcml_specification.jl`](../test/mrcml_specification.jl) (standalone
constraint, gradient, permutation and rank checks without posterior sampling), and
`test/cr6_prior_defaults_mgmfrm_sbc.jl` (including the Givens density/Jacobian
checks). Inspect a selected test's setup and scope: the last file also contains
short fits and SBC checks, and its filename alone does not define a small test.

When refactoring, preserve validation order, named record fields, label order,
chain/iteration alignment and numerical defaults. Names should distinguish a
target, a fit record, a draw matrix and a computed report. Comments should
explain statistical or storage invariants; tests should check the affected
behavior, not just the new file arrangement.
