# Bayesian Workflow

A many-facet analysis is more than a sampling call. The rating design,
identification constraints, priors, sampler behavior, predictive performance,
and reporting scope all affect what can be interpreted.

## 1. Validate the Rating Design

Create [`FacetData`](@ref) from long-format ratings and run
[`validate_design`](@ref). Review:

- person, rater, item, and category coverage;
- disconnected or weakly linked rating blocks;
- skipped or sparse categories;
- repeated ratings and optional time or order fields;
- anchors and optional grouping variables;
- the distinction between planned and accidental missingness.

[`coverage_summary`](@ref), [`coverage_matrix`](@ref),
[`rater_overlap`](@ref), [`anchor_linking_summary`](@ref), and
[`rating_design_audit`](@ref) provide additional review rows. These checks do
not make non-random rater assignment ignorable.

## 2. Inspect the Model Before Fitting

Create an [`mfrm_spec`](@ref) and inspect:

- [`model_equation`](@ref) for the likelihood and source contract;
- [`constraint_table`](@ref) and [`identification_declarations`](@ref) for the
  gauge and reference rules;
- [`getdesign`](@ref) for the identified parameter vector;
- [`model_manifest`](@ref) for a portable summary of data, model, and design.

Specified configurations are not necessarily fit-supported. The support table
in [Scope and Releases](scope.md) governs whether a fitting call is available.

## 3. Check Prior Implications

Choose [`MFRMPrior`](@ref) scales that match the analysis context and run
[`prior_predictive_check`](@ref). Look for implausible score distributions,
category use, or facet ranges before inspecting the observed-data posterior.

The experimental generalized configurations use their documented built-in
raw-coordinate priors. Custom generalized prior objects are not supported.

## 4. Fit and Diagnose

Use [`fit`](@ref) for supported models. Set an integer seed when replay is
required and record the sampler controls. Multiple chains are required for
meaningful between-chain convergence checks.

Review:

- [`sampler_diagnostics`](@ref) for chain and HMC behavior;
- [`mcmc_diagnostics`](@ref) for R-hat and ESS;
- [`parameter_block_diagnostics`](@ref) for block-level patterns;
- [`diagnostics`](@ref) for the compact combined status.

A completed run is not automatically a trustworthy run. Divergences,
tree-depth saturation, low ESS, unstable R-hat, non-finite evaluations, or
constraint failures require investigation.

## 5. Examine Predictions and Residuals

Use [`posterior_predictive_check`](@ref),
[`predictive_check_summary`](@ref), and [`calibration_table`](@ref) to compare
observed and replicated outcomes. [`predictive_residuals`](@ref),
[`residual_summary`](@ref), [`fit_stats`](@ref), and
[`rater_diagnostics`](@ref) help locate misfit.

DFF rows are screening information unless the fitted model explicitly supports
the corresponding identified effect. Statistical differences should be
reported separately from practical magnitude and substantive interpretation.

## 6. Compare Models Carefully

WAIC, LOO, PSIS-LOO, and K-fold summaries require compatible observations and
an explicit prediction target. Inspect pointwise influence, Pareto-k, and
held-out diagnostics. Relative weights are not posterior model probabilities,
and a ranking is not by itself a superiority claim.

Sensitivity work should cover defensible prior choices and any threshold,
anchor, dimensionality, or Q-matrix decisions that could change the
interpretation.

## 7. Report the Boundary

[`posterior_summary`](@ref), [`fair_average_summary`](@ref),
[`separation_reliability_summary`](@ref), [`wright_map_data`](@ref), and other
reporting helpers return table-oriented results. [`fit_report`](@ref) combines
the complete machine-oriented sections. Use `fit_report(fit; view = :public)`
or [`fit_report_public`](@ref) for a reader-facing structured projection, and
[`fit_report_markdown`](@ref) for a Markdown preview.

A report should state:

- model family, threshold regime, dimensions, and constraints;
- rating-design limitations;
- priors and sampler controls;
- convergence and predictive diagnostics;
- the prediction target for model comparison;
- unsupported features and the limits of generalization.

Experimental fixed-Q MGMFRM results must not be generalized to exploratory
multidimensional models or freely estimated correlation structures.
